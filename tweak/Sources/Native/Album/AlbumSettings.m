#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(@"Header", @[
            SGOptionRow(SGLocalized(@"Artwork background"), nil, SGKeyAlbumBackdrop),
        ]),
        SGSection(@"Hide in the header", @[
            SGHideRow(SGLocalized(@"Explore (video deck)"), nil, SGHideAlbumExplore),
            SGHideRow(SGLocalized(@"Add to library"), nil, SGHideAlbumAddTo),
            SGHideRow(SGLocalized(@"Download"), nil, SGHideAlbumDownload),
            SGHideRow(SGLocalized(@"More options"), nil, SGHideAlbumMore),
        ]),
        SGNotedSection(@"Hide on the page", @[
            SGHideRow(SGLocalized(@"More by the artist"), nil, SGHideAlbumMoreBy),
            SGHideRow(SGLocalized(@"Related music videos"), nil, SGHideAlbumVideos),
            SGHideRow(@"Concerts", nil, SGHideAlbumConcerts),
            SGHideRow(SGLocalized(@"Merch"), nil, SGHideAlbumMerch),
            SGHideRow(SGLocalized(@"You might also like"), nil, SGHideAlbumYouMightLike),
        ], @"Works only with Spotify in English."),
    ];
    return [[SGModPage alloc] initWithTitle:@"Album" intro:nil sections:sections footer:nil];
}
