// Small Objective-C surface over the parts of Scintilla/Lexilla that use C++ types,
// so Swift can drive them.
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SciBridge : NSObject
/// Attach a Lexilla lexer (e.g. "python", "cpp", "json") to the view. Returns NO if unknown.
+ (BOOL)setLexer:(NSString *)name onView:(ScintillaView *)view;
/// The notification code (SCN_*) carried by a Scintilla notification.
+ (unsigned int)codeOfNotification:(SCNotification *)notification;
@end

NS_ASSUME_NONNULL_END
