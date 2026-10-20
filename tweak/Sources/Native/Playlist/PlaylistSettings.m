#import "Core/SGLocalization.h"
#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Playlists" intro:nil sections:@[
        SGSection(@"Header", @[
            SGOptionRow(SGLocalized(@"Artwork background"), nil, SGKeyPlaylistBackdrop),
        ]),
        SGSection(@"Hide in the playlist header", @[
            SGHideRow(SGLocalized(@"Cover artwork"), nil, SGHidePlaylistArtwork),
            SGHideRow(@"Description", nil, SGHidePlaylistDescription),
            SGHideRow(SGLocalized(@"Creator and collaborators"), nil, SGHidePlaylistCreator),
            SGHideRow(SGLocalized(@"Length and saves"), nil, SGHidePlaylistLength),
        ]),
        SGSection(@"Hide playlist buttons", @[
            SGHideRow(SGLocalized(@"Video"), nil, SGHidePlaylistVideo),
            SGHideRow(SGLocalized(@"Add to library"), nil, SGHidePlaylistAddTo),
            SGHideRow(SGLocalized(@"Download"), nil, SGHidePlaylistDownload),
            SGHideRow(SGLocalized(@"Share"), nil, SGHidePlaylistShare),
            SGHideRow(SGLocalized(@"More"), nil, SGHidePlaylistMore),
        ]),
        SGSection(@"Hide above the tracks", @[
            SGHideRow(SGLocalized(@"Curation pills"), nil, SGHidePlaylistPills),
            SGHideRow(SGLocalized(@"Find and sort bar"), nil, SGHidePlaylistFind),
        ]),
    ] footer:nil];
}
