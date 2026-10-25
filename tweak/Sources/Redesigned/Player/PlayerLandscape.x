// Player redesign: the player or lyrics turn sideways with the phone onto a landscape screen of their own. The cover
// is on the left with the title, the artist and the controls under it, and the lines are on the right.
// A track without lines keeps the screen: the cover grows to the screen's height with the title and the
// controls beside it, until a track with lines comes on.
// The controls fade after a few seconds without a touch and come back at a tap, as in the player: the
// tap that brings them back lands on a clear shield over the screen, so it never seeks. The button beside
// the title turns the screen back to portrait, as VoiceOver's escape does, for a phone held flat or on its
// side; the screen stays shut then until the phone has stood upright again.
//
// Spotify's iPhone Info.plist allows portrait only, and UIKit asks the app delegate's
// -application:supportedInterfaceOrientationsForWindow: in its place where there is one. So the delegate
// answers landscape for this screen's own window and portrait for every other, and the scene is asked to
// turn while the window is up. Spotify's own windows never turn.
#import <objc/runtime.h>
#import <math.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Player.h"

static const CGFloat kSide = 32, kCoverGap = 16, kControlSide = 44, kColumnShare = 0.38;
// The title and the controls beside the cover of a track without lines.
static const CGFloat kBareInfoWidth = 300, kBareControlsWidth = 200;
static const NSTimeInterval kLandscapeRest = 4;
static const CGFloat kProgressHeight = 62;

static UIWindow *sg_window;
static __weak UIWindowScene *sg_playerScene;
static __weak UIViewController *sg_visiblePlayer;
static __weak UIWindow *sg_previousKeyWindow;
static void orientationChanged(void);
// Shut from the screen: turning the phone again does not reopen it until it has stood upright.
static BOOL sg_shut;

#pragma mark - the screen

// UIKit's slider supplies the adjustable VoiceOver trait; use a predictable five-second step.
@interface SGRLandscapeProgressSlider : UISlider
@end
@implementation SGRLandscapeProgressSlider
- (void)step:(float)seconds {
    if (!self.enabled) return;
    self.value = MIN(self.maximumValue, MAX(self.minimumValue, self.value + seconds));
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)accessibilityIncrement { [self step:5]; }
- (void)accessibilityDecrement { [self step:-5]; }
@end

@interface SGRLandscapeLyricsController : UIViewController <SGPlayerStateObserver, UIGestureRecognizerDelegate>
- (void)stopProgress;
@end

@implementation SGRLandscapeLyricsController {
    SGRArtworkField *_field;
    UIImageView *_cover;
    SGMarqueeLabel *_title, *_artist;
    UIStackView *_controls;
    UIButton *_play, *_close;
    UIView *_progress;
    SGRLandscapeProgressSlider *_slider;
    UILabel *_elapsed, *_remaining;
    NSTimer *_progressTimer;
    BOOL _scrubbing;
    NSString *_scrubTrack, *_progressTrack;
    CFTimeInterval _seekUntil;
    double _seekPosition;
    UIView *_stage;   // the lines' own view: the karaoke view dims every sibling it has
    SGRKaraokeView *_lyrics;
    NSTimer *_rest;
    UITapGestureRecognizer *_hide;   // only while the controls are up
    UIView *_shield;                 // only while they are not: the touch that brings them back
    BOOL _bare;                      // the track playing has no lines: the cover takes the screen
}

// Portrait once the screen is on its way out, or the scene could not turn back while it fades.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return sg_window.rootViewController == self ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

// A glyph in a 44pt square, so the touch is as large as the default control whatever the glyph's size.
static UIButton *controlButton(NSString *symbol, CGFloat size, NSString *label, SEL action, id target) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = SGLocalized(label);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:kControlSide].active = YES;
    [button.heightAnchor constraintEqualToConstant:kControlSide].active = YES;
    return button;
}

// The title and the artist at the phone's text size, capped where the column still holds a cover.
- (void)applyFonts {
    _title.font = SGRFont(UIFontTextStyleTitle3, UIFontWeightBold, UIContentSizeCategoryExtraExtraExtraLarge);
    _artist.font = SGRFont(UIFontTextStyleCallout, UIFontWeightRegular, UIContentSizeCategoryExtraExtraExtraLarge);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self applyFonts];
    [self.view setNeedsLayout];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.view.accessibilityViewIsModal = YES;

    // The player's own field behind the screen, so the colors carry over from the portrait player.
    _field = [[SGRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.showsBackdrop = YES;
    _field.fluid = YES;
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (art) [_field setArtwork:art identity:identity animated:NO];
    [self.view addSubview:_field];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = SGRRadiusArtwork;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.image = art;
    [self.view addSubview:_cover];

    // A title or artist too long for the column scrolls, as the player's own do.
    _title = [SGMarqueeLabel new];
    _title.textColor = UIColor.whiteColor;
    _artist = [SGMarqueeLabel new];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [self applyFonts];
    [self.view addSubview:_title];
    [self.view addSubview:_artist];
    // Where the Music app keeps a song's ⋯: the way back to the player, for a phone that is not turned back.
    _close = controlButton(@"arrow.down.right.and.arrow.up.left", 17, @"Exit full screen", @selector(turnBack), self);
    [self.view addSubview:_close];

    _play = controlButton(@"pause.fill", 30, @"Pause", @selector(togglePlay), self);
    _controls = [[UIStackView alloc] initWithArrangedSubviews:@[
        controlButton(@"backward.fill", 24, @"Previous track", @selector(previous), self), _play,
        controlButton(@"forward.fill", 24, @"Next track", @selector(next), self),
    ]];
    _controls.distribution = UIStackViewDistributionEqualSpacing;
    _controls.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:_controls];

    _progress = [UIView new];
    _slider = [SGRLandscapeProgressSlider new];
    _slider.minimumValue = 0;
    _slider.tintColor = SGRPrimary();
    _slider.accessibilityLabel = SGLocalized(@"Playback position");
    [_slider addTarget:self action:@selector(beginScrubbing) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(progressChanged) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(finishScrubbing) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_slider addTarget:self action:@selector(cancelScrubbing) forControlEvents:UIControlEventTouchCancel];
    [_progress addSubview:_slider];
    _elapsed = [UILabel new];
    _remaining = [UILabel new];
    for (UILabel *label in @[_elapsed, _remaining]) {
        label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        label.textColor = SGRSecondary();
        label.isAccessibilityElement = NO; // The slider announces both times as one adjustable element.
        [_progress addSubview:label];
    }
    _remaining.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:_progress];

    _stage = [UIView new];
    [self.view addSubview:_stage];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_stage addSubview:_lyrics];
    __weak SGRLandscapeLyricsController *weakSelf = self;
    _lyrics.browsingBegan = ^{ [weakSelf rest]; };

    _hide = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rest)];
    _hide.delegate = self;
    [self.view addGestureRecognizer:_hide];
    _shield = [[UIView alloc] initWithFrame:self.view.bounds];
    _shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _shield.accessibilityElementsHidden = YES;
    [_shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wake)]];
    [_shield addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wake)]];
    [self updateBare:YES];
    SGAddPlayerStateObserver(self);
    [self playerStateDidChange:SGPlayerState()];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged)
                                               name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    // The shield is hidden from VoiceOver, so turning it on brings the controls back and keeps them.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(wake)
                                               name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_rest invalidate];
    [_progressTimer invalidate];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat column = round(safe.size.width * kColumnShare);
    CGFloat left = CGRectGetMinX(safe) + kSide;
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat textHeight = MAX(titleHeight + artistHeight, kControlSide), controlsHeight = kControlSide;
    CGFloat width = MAX(3 * kControlSide, column - kSide);
    CGFloat side = MAX(0, MIN(width, safe.size.height - 2 * kSide - textHeight - controlsHeight - kProgressHeight - kCoverGap));
    CGFloat top = CGRectGetMidY(safe) - (side + kCoverGap + textHeight + kProgressHeight + controlsHeight) / 2;
    _cover.frame = CGRectMake(left + (width - side) / 2, top, side, side);
    // The close button at the text's trailing end, its glyph (about 20pt in the 44pt square) at the cover's edge.
    CGFloat textTop = CGRectGetMaxY(_cover.frame) + kCoverGap;
    _close.frame = CGRectMake(left + width - kControlSide, textTop + (textHeight - kControlSide) / 2, kControlSide, kControlSide);
    _title.frame = CGRectMake(left, textTop + (textHeight - titleHeight - artistHeight) / 2, width - kControlSide, titleHeight);
    _artist.frame = CGRectMake(left, CGRectGetMaxY(_title.frame), width - kControlSide, artistHeight);
    _progress.frame = CGRectMake(left, textTop + textHeight, width, kProgressHeight);
    _controls.frame = CGRectMake(left, CGRectGetMaxY(_progress.frame), width, controlsHeight);
    CGFloat linesLeft = left + width + kSide;
    _stage.frame = CGRectMake(linesLeft, CGRectGetMinY(safe), CGRectGetMaxX(safe) - linesLeft, safe.size.height);
    _lyrics.frame = _stage.bounds;
    if (!_bare) { [self layoutProgress]; return; }

    // The cover at the screen's height and the title and controls beside it, the two centered as one. The
    // lines keep their place above, so they come back from where they will stand.
    side = safe.size.height - 2 * kSide;
    CGFloat info = MIN(kBareInfoWidth, safe.size.width - 3 * kSide - side);
    CGFloat x = CGRectGetMidX(safe) - (side + kSide + info) / 2;
    _cover.frame = CGRectMake(x, CGRectGetMidY(safe) - side / 2, side, side);
    CGFloat infoLeft = x + side + kSide;
    textTop = CGRectGetMidY(safe) - (textHeight + kProgressHeight + controlsHeight) / 2;
    _close.frame = CGRectMake(infoLeft + info - kControlSide, textTop + (textHeight - kControlSide) / 2, kControlSide, kControlSide);
    _title.frame = CGRectMake(infoLeft, textTop + (textHeight - titleHeight - artistHeight) / 2, info - kControlSide, titleHeight);
    _artist.frame = CGRectMake(infoLeft, CGRectGetMaxY(_title.frame), info - kControlSide, artistHeight);
    _progress.frame = CGRectMake(infoLeft, textTop + textHeight, info, kProgressHeight);
    _controls.frame = CGRectMake(infoLeft, CGRectGetMaxY(_progress.frame), MIN(kBareControlsWidth, info), controlsHeight);
    [self layoutProgress];
}

- (void)layoutProgress {
    CGFloat width = _progress.bounds.size.width;
    _slider.frame = CGRectMake(0, 0, width, 44);
    _elapsed.frame = CGRectMake(0, 44, width / 2, 18);
    _remaining.frame = CGRectMake(width / 2, 44, width / 2, 18);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self restartRest];
    [self updateProgress];
    __weak SGRLandscapeLyricsController *weakSelf = self;
    [_progressTimer invalidate];
    _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf updateProgress];
    }];
}

- (void)stopProgress {
    [_progressTimer invalidate];
    _progressTimer = nil;
    [_rest invalidate];
    _rest = nil;
    _scrubbing = NO;
    _scrubTrack = nil;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopProgress];
}

// The window comes up clear and fades in as the scene turns, so the screen is never seen laid out upright.
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    UIWindow *window = self.view.window;
    if (!window || window != sg_window || size.width <= size.height) return;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        window.alpha = 1;
    } completion:nil];
}

- (void)artworkChanged {
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (!art) return;
    // On the field's clock, so the cover and the colors behind it change as one.
    UIImageView *cover = _cover;
    [UIView transitionWithView:cover duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ cover.image = art; } completion:nil];
    [_field setArtwork:art identity:identity animated:YES];
}

// Lines in: the lines' layout at once. None (the player's own verdict, after its grace): the cover's.
// Otherwise the layout stays, so a track change does not flash between the two. A track change alone never
// takes the lines away: the player may not have heard of it yet, and would still count the last one's grace.
- (void)updateBare:(BOOL)mayGoBare {
    BOOL bare = _bare;
    if (!SGRPlayerLyricsOpen()) bare = YES;
    else if (SGRPlayerLyricsAvailable()) bare = NO;
    else if (mayGoBare && SGRPlayerLyricsNone()) bare = YES;
    if (bare == _bare) return;
    _bare = bare;
    SGLog(@"redesign player: landscape %@", bare ? @"without lines, the cover takes the screen" : @"with lines");
    // The lines leave the window while they are away, so their display link stops with them.
    if (!bare) [self.view insertSubview:_stage aboveSubview:_controls];
    UIView *stage = _stage;
    void (^change)(void) = ^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        stage.alpha = bare ? 0 : 1;
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (self->_bare) [stage removeFromSuperview];
    };
    if (self.view.window) SGRAnimateLayout(self.view, change, done);
    else {
        change();
        done(YES);
    }
    // Without lines there is nothing to read past the controls, so they stay.
    if (bare) [self wake];
    else [self restartRest];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!state) return;
    [self updateBare:NO];
    _title.text = state.track.trackTitle;
    _artist.text = state.track.artistName;
    [_play setImage:[UIImage systemImageNamed:state.isPaused ? @"play.fill" : @"pause.fill" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    _play.accessibilityLabel = SGLocalized(state.isPaused ? @"Play" : @"Pause");
    _field.motionHeld = state.isPaused;
    [self updateProgress];
    id player = self.player;
    _play.enabled = [player respondsToSelector:state.isPaused ? @selector(resume:) : @selector(pause:)];
    ((UIButton *)_controls.arrangedSubviews.firstObject).enabled = [player respondsToSelector:@selector(skipToPreviousTrackWithOptions:)];
    ((UIButton *)_controls.arrangedSubviews.lastObject).enabled = [player respondsToSelector:@selector(skipToNextTrackWithOptions:)];
    // A pause brings the controls back and keeps them; playing again, from here or anywhere, starts the
    // clock. The tap on the play button cannot: the state saying so arrives a beat after it.
    if (state.isPaused) [self setControlsShown:YES];
    else if (!_rest && !_shield.superview) [self restartRest];
}

#pragma mark - controls

static NSString *clockText(double seconds) {
    NSInteger whole = (NSInteger)MAX(0, floor(seconds));
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(whole / 60), (long)(whole % 60)];
}

- (void)showPosition:(double)position duration:(double)duration {
    _elapsed.text = clockText(position);
    _remaining.text = [@"−" stringByAppendingString:clockText(MAX(0, duration - position))];
    _slider.accessibilityValue = [NSString stringWithFormat:SGLocalized(@"%@ of %@"), clockText(position), clockText(duration)];
}

- (void)updateProgress {
    if (self.view.window.hidden || self.view.window.windowScene.activationState != UISceneActivationStateForegroundActive) return;
    SPTPlayerState *state = SGPlayerState();
    NSString *track = SGURIString(state.track.URI);
    if (![_progressTrack isEqualToString:track]) {
        _progressTrack = [track copy];
        _seekUntil = 0;
        _scrubTrack = nil; // A drag started on another song must never seek this one.
    }
    double duration = state.duration;
    NSInteger ms = SGKaraokePositionMs();
    BOOL valid = track.length && isfinite(duration) && duration > 0 && duration < (double)(NSIntegerMax / 1000) && ms >= 0;
    _slider.enabled = valid && [SGKaraokePlayer() respondsToSelector:@selector(seekTo:)];
    if (_scrubbing) return;
    _slider.maximumValue = valid ? duration : 1;
    double position = valid ? MIN(duration, MAX(0, ms / 1000.0)) : 0;
    if (valid && _seekUntil > CACurrentMediaTime() && fabs(position - _seekPosition) > 1) position = MIN(duration, _seekPosition);
    else _seekUntil = 0;
    _slider.value = position;
    if (valid) [self showPosition:position duration:duration];
    else {
        _elapsed.text = _remaining.text = @"–:––";
        _slider.accessibilityValue = SGLocalized(@"Unavailable");
    }
}

- (void)beginScrubbing {
    _scrubbing = YES;
    _scrubTrack = [SGURIString(SGPlayerState().track.URI) copy];
    [_rest invalidate];
    _rest = nil;
}

- (void)progressChanged {
    if (!_slider.enabled) return;
    [self showPosition:_slider.value duration:_slider.maximumValue];
    // VoiceOver adjusts without a touch-down/up pair.
    if (!_scrubbing) {
        _scrubTrack = [SGURIString(SGPlayerState().track.URI) copy];
        [self finishScrubbing];
    }
}

- (void)finishScrubbing {
    NSString *track = SGURIString(SGPlayerState().track.URI);
    double duration = SGPlayerState().duration;
    if (_slider.enabled && _scrubTrack.length && [_scrubTrack isEqualToString:track] && isfinite(_slider.value) &&
        isfinite(duration) && duration > 0 && duration < (double)(NSIntegerMax / 1000)) {
        _seekPosition = MIN(duration, MAX(0, _slider.value));
        _seekUntil = CACurrentMediaTime() + 1.5;
        SGKaraokeSeek((NSInteger)(_seekPosition * 1000));
    }
    [self cancelScrubbing];
}

- (void)cancelScrubbing {
    _scrubbing = NO;
    _scrubTrack = nil;
    [self updateProgress];
    [self restartRest];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return NO;
    }
    return YES;
}

- (id<SPTPlayer>)player {
    id player = SGKaraokePlayer();
    return [player conformsToProtocol:@protocol(SPTPlayer)] || [player respondsToSelector:@selector(pause:)] ? player : nil;
}

- (void)togglePlay {
    id<SPTPlayer> player = self.player;
    if (SGPlayerState().isPaused) {
        if ([player respondsToSelector:@selector(resume:)]) [player resume:nil];
    } else if ([player respondsToSelector:@selector(pause:)]) [player pause:nil];
    [self restartRest];
}

- (void)previous {
    id<SPTPlayer> player = self.player;
    if ([player respondsToSelector:@selector(skipToPreviousTrackWithOptions:)]) [player skipToPreviousTrackWithOptions:nil];
    [self restartRest];
}

- (void)next {
    id<SPTPlayer> player = self.player;
    if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:)]) [player skipToNextTrackWithOptions:nil];
    [self restartRest];
}

- (void)turnBack {
    sg_shut = YES;
    SGRPlayerShowLandscape(NO);
}

// VoiceOver's two-finger scrub.
- (BOOL)accessibilityPerformEscape {
    [self turnBack];
    return YES;
}

// The lines on their own, unless VoiceOver needs the controls to be there.
- (void)rest {
    if (!_bare && !_scrubbing && !UIAccessibilityIsVoiceOverRunning()) [self setControlsShown:NO];
}

- (void)wake {
    [self setControlsShown:YES];
}

- (void)setControlsShown:(BOOL)shown {
    [_rest invalidate];
    _rest = nil;
    _hide.enabled = shown;
    if (shown) [_shield removeFromSuperview];
    else if (!_shield.superview) {
        _shield.frame = self.view.bounds;
        [self.view addSubview:_shield];
    }
    // Back at a tap with the Kit's response, from where a fade out is; they go with the slow fade, as the
    // portrait player's do (PlayerLyrics.x).
    SGRAnimate(shown ? SGRMotionRespond : SGRMotionFade, ^{
        for (UIView *view in @[self->_controls, self->_close, self->_title, self->_artist, self->_progress]) view.alpha = shown ? 1 : 0;
        self->_lyrics.extrasHidden = !shown;
    }, nil);
    if (shown) [self restartRest];
}

- (void)restartRest {
    [_rest invalidate];
    _rest = nil;
    if (_bare || _scrubbing || !SGEnabled(SGRKeyLyricsAutoHide) || SGPlayerState().isPaused || UIAccessibilityIsVoiceOverRunning()) return;
    __weak SGRLandscapeLyricsController *weakSelf = self;
    _rest = [NSTimer scheduledTimerWithTimeInterval:kLandscapeRest repeats:NO block:^(NSTimer *timer) {
        // A sheet over the lines (a line's meanings) keeps them up, and the clock runs again behind it.
        SGRLandscapeLyricsController *strongSelf = weakSelf;
        if (strongSelf.presentedViewController) [strongSelf restartRest];
        else [strongSelf rest];
    }];
}

@end

#pragma mark - turning

static UIInterfaceOrientationMask (*sg_origOrientations)(id, SEL, UIApplication *, UIWindow *);

static UIInterfaceOrientationMask orientationsFor(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if (window && window == sg_window) return UIInterfaceOrientationMaskLandscape;
    return sg_origOrientations ? sg_origOrientations(self, _cmd, application, window) : UIInterfaceOrientationMaskPortrait;
}

// The delegate's own answer stays for every window but the landscape one; one that has none answers
// portrait, which is what the Info.plist said.
static void answerForOrientations(void) {
    static BOOL done;
    id delegate = UIApplication.sharedApplication.delegate;
    if (done || !delegate) return;
    done = YES;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod([delegate class], selector);
    if (method) sg_origOrientations = (void *)method_setImplementation(method, (IMP)orientationsFor);
    else class_addMethod([delegate class], selector, (IMP)orientationsFor, "Q@:@@");
    SGLog(@"redesign player: landscape lyrics answer for %@ (%@)", NSStringFromClass([delegate class]), method ? @"its own answer kept" : @"portrait otherwise");
}

// A landscape window still clear when no turn is coming to fade it in.
static void reveal(UIWindow *window) {
    if (window && window == sg_window && window.alpha < 1) SGRAnimate(SGRMotionFade, ^{ window.alpha = 1; }, nil);
}

static void requestOrientations(UIWindowScene *scene, UIInterfaceOrientationMask mask) {
    __weak UIWindow *window = sg_window;
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            SGLog(@"redesign player: the scene did not turn: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                // A delayed failure for an older window must not close its replacement (or reopen it).
                if (mask != UIInterfaceOrientationMaskLandscape || !window || window != sg_window) return;
                if (UIInterfaceOrientationIsLandscape(scene.interfaceOrientation)) reveal(window);
                else {
                    sg_shut = YES; // Do not retry on every device notification; upright resets this.
                    SGRPlayerShowLandscape(NO);
                }
            });
        }];
    }
}

void SGRPlayerLandscapeLinesChanged(void) {
    id screen = sg_window.rootViewController;
    if ([screen isKindOfClass:SGRLandscapeLyricsController.class]) [screen updateBare:YES];
}

void SGRPlayerShowLandscape(BOOL show) {
    UIWindowScene *scene = sg_window.windowScene ?: sg_playerScene;
    if (!scene) return;
    if (show && (!sg_visiblePlayer || scene.activationState != UISceneActivationStateForegroundActive)) return;
    if (show && !sg_window) {
        answerForOrientations();
        for (UIWindow *window in scene.windows) {
            if (window.isKeyWindow) { sg_previousKeyWindow = window; break; }
        }
        sg_window = [[UIWindow alloc] initWithWindowScene:scene];
        sg_window.windowLevel = UIWindowLevelNormal + 1;
        // The window is the mod's own, so what it presents (Sing's alerts, a line's meanings) is dark too.
        sg_window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        sg_window.alpha = 0;
        sg_window.rootViewController = [SGRLandscapeLyricsController new];
        [sg_window makeKeyAndVisible];
        requestOrientations(scene, UIInterfaceOrientationMaskLandscape);
        if (UIInterfaceOrientationIsLandscape(scene.interfaceOrientation)) reveal(sg_window);
        __weak UIWindow *requestedWindow = sg_window;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!requestedWindow || requestedWindow != sg_window) return;
            if (UIInterfaceOrientationIsLandscape(scene.interfaceOrientation)) reveal(requestedWindow);
            else { sg_shut = YES; SGRPlayerShowLandscape(NO); }
        });
        SGLog(@"redesign player: the lyrics turn sideways");
    } else if (!show && sg_window) {
        UIWindow *window = sg_window;
        UIWindow *previous = sg_previousKeyWindow;
        sg_previousKeyWindow = nil;
        sg_window = nil;
        [(SGRLandscapeLyricsController *)window.rootViewController stopProgress];
        window.userInteractionEnabled = NO;
        // A sheet up over the lines (a line's meanings) goes with them, or it would be left on a hidden window.
        [window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        if (@available(iOS 16.0, *)) [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        requestOrientations(scene, UIInterfaceOrientationMaskPortrait);
        // Faded out as the scene turns back; the player is key again once it is gone, unless the lines came
        // back meanwhile.
        SGRAnimate(SGRMotionFade, ^{ window.alpha = 0; }, ^(BOOL finished) {
            window.hidden = YES;
            if (sg_window) return;
            if (previous && !previous.hidden && previous.windowScene == scene) {
                [previous makeKeyWindow];
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
                return;
            }
            for (UIWindow *other in scene.windows) {
                if (other != window && !other.hidden && other.windowLevel == UIWindowLevelNormal) {
                    [other makeKeyWindow];
                    break;
                }
            }
        });
        SGLog(@"redesign player: the lyrics turn back");
    }
}

void SGRPlayerLandscapeSetVisible(UIViewController *player, BOOL visible) {
    if (visible) {
        sg_visiblePlayer = player;
        sg_playerScene = player.viewIfLoaded.window.windowScene;
        dispatch_async(dispatch_get_main_queue(), ^{ orientationChanged(); });
    } else if (sg_visiblePlayer == player) {
        sg_visiblePlayer = nil;
        SGRPlayerShowLandscape(NO);
        sg_playerScene = nil;
    }
}

static void orientationChanged(void) {
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (UIDeviceOrientationIsLandscape(orientation)) {
        BOOL allowed = SGEnabled(SGRKeyPlayerLandscape) ||
                       (SGEnabled(SGRKeyLyricsLandscape) && SGRPlayerLyricsOpen());
        if (!sg_shut && allowed && sg_visiblePlayer) SGRPlayerShowLandscape(YES);
    } else if (orientation == UIDeviceOrientationPortrait) {
        sg_shut = NO;
        SGRPlayerShowLandscape(NO);
    }
}

%ctor {
    if (!SGRedesignedUI()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ orientationChanged(); });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ SGRPlayerShowLandscape(NO); });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ orientationChanged(); });
        }];
    });
}
