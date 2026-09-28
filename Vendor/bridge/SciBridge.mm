#import "SciBridge.h"
#include "ILexer.h"
#include "Lexilla.h"

@implementation SciBridge

+ (BOOL)setLexer:(NSString *)name onView:(ScintillaView *)view {
	Scintilla::ILexer5 *lexer = CreateLexer(name.UTF8String);
	if (!lexer) {
		return NO;
	}
	[view message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
	return YES;
}

+ (unsigned int)codeOfNotification:(SCNotification *)notification {
	return notification->nmhdr.code;
}

@end
