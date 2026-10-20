#import "SGLocalization.h"

BOOL SGUsesFrench(void) {
    static BOOL french;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *language = NSLocale.preferredLanguages.firstObject;
        NSString *code = [NSLocale componentsFromLocaleIdentifier:language ?: @"en"][NSLocaleLanguageCode];
        french = [code.lowercaseString isEqualToString:@"fr"];
    });
    return french;
}

static NSString *SGCanonicalText(NSString *text) {
    return [[[[text stringByReplacingOccurrencesOfString:@"’" withString:@"'"]
                  stringByReplacingOccurrencesOfString:@"‘" withString:@"'"]
                  stringByReplacingOccurrencesOfString:@"“" withString:@"\""]
                  stringByReplacingOccurrencesOfString:@"”" withString:@"\""];
}

NSString *SGLocalized(NSString *text) {
    if (!text.length || !SGUsesFrench()) return text;
    static NSDictionary<NSString *, NSString *> *french;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        french = @{
#include "Localization/SGFrench.inc"
        };
    });
    return french[SGCanonicalText(text)] ?: text;
}
