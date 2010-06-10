/*
	OOMeshLexer.m
	
	
	Copyright © 2010 Jens Ayton

	Permission is hereby granted, free of charge, to any person obtaining a
	copy of this software and associated documentation files (the “Software”),
	to deal in the Software without restriction, including without limitation
	the rights to use, copy, modify, merge, publish, distribute, sublicense,
	and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
	THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
	DEALINGS IN THE SOFTWARE.
*/

#import "OOMeshLexer.h"
#import "OOProblemReporting.h"



@interface OOMeshLexer (Private)

- (NSString *) decodeEscapedString;

@end


@implementation OOMeshLexer

- (id) initWithURL:(NSURL *)inURL issues:(id <OOProblemReporting>)issues
{
	if ([inURL isFileURL])
	{
		NSError *error = nil;
		NSData *fileData = [[NSData alloc] initWithContentsOfURL:inURL options:0 error:&error];
		if (fileData == nil)
		{
			OOReportError(issues, @"The document could not be loaded, because an error occurred: %@", [error localizedDescription]);
			return nil;
		}
		return [self initWithData:fileData issues:issues];
	}
	else
	{
		[NSException raise:NSInvalidArgumentException format:@"OOMeshLexer does not support non-file URLs such as %@", [inURL absoluteURL]];
	}
	
	return nil;
}


- (id) initWithPath:(NSString *)inPath issues:(id <OOProblemReporting>)issues
{
	return [self initWithURL:[NSURL fileURLWithPath:inPath] issues:issues];
}


- (id) initWithData:(NSData *)inData issues:(id <OOProblemReporting>)issues
{
	if ([inData length] == 0)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		_issues = [issues retain];
		_data = [inData retain];
		
		_state.tokenType = kOOMeshTokenInvalid;
		_state.cursor = [inData bytes];
		_state.end = _state.cursor + [inData length];
		_state.tokenLength = 0;
		_state.lineNumber = 1;
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_issues);
	DESTROY(_data);
	DESTROY(_tokenString);
	
	[super dealloc];
}


- (NSInteger) lineNumber
{
	return _state.lineNumber;
}


- (OOMeshTokenType) currentTokenType
{
	if (_state.tokenType != kOOMeshTokenStringWithEscapes)  return _state.tokenType;
	else  return kOOMeshTokenString;
}


- (NSString *) currentTokenString
{
	if (_tokenString == nil)
	{
		if (_state.tokenType == kOOMeshTokenString)
		{
			_tokenString = [[NSString alloc] initWithBytes:_state.cursor + 1
													length:_state.tokenLength - 2
												  encoding:NSUTF8StringEncoding];
		}
		else if (_state.tokenType == kOOMeshTokenStringWithEscapes)
		{
			_tokenString = [[self decodeEscapedString] copy];
		}
		else
		{
			_tokenString = [[NSString alloc] initWithBytes:_state.cursor 
													length:_state.tokenLength
												  encoding:NSUTF8StringEncoding];
		}
		[[_tokenString retain] autorelease];
	}
	
	return _tokenString;
}


- (NSString *) currentTokenDescription
{
	switch (_state.tokenType)
	{
		case kOOMeshTokenKeyword:
		{
			NSString *format = OOLocalizeProblemString(_issues, @"\"%@\"");
			return $sprintf(format, [self currentTokenString]);
		}
			
		case kOOMeshTokenString:
		case kOOMeshTokenStringWithEscapes:
			return OOLocalizeProblemString(_issues, @"string");
			
		case kOOMeshTokenNatural:
			return OOLocalizeProblemString(_issues, @"integer");
			
		case kOOMeshTokenReal:
			return OOLocalizeProblemString(_issues, @"number");
			
		case kOOMeshTokenNewline:
			return OOLocalizeProblemString(_issues, @"end of line");
			
		case kOOMeshTokenColon:
		case kOOMeshTokenComma:
		case kOOMeshTokenOpenBrace:
		case kOOMeshTokenCloseBrace:
		case kOOMeshTokenOpenBracket:
		case kOOMeshTokenCloseBracket:
			return [self currentTokenString];
			
		case kOOMeshTokenEOF:
			return OOLocalizeProblemString(_issues, @"end of file");
			
		case kOOMeshTokenInvalid:
			break;
	}
	return OOLocalizeProblemString(_issues, @"invalid token");
}


- (BOOL) getNatural:(uint64_t *)outNatural
{
	NSParameterAssert(outNatural != NULL);
	
	if (_state.tokenType == kOOMeshTokenNatural)
	{
		uint64_t result = 0;
		const uint8_t *str = _state.cursor;
		size_t rem = _state.tokenLength;
		
		if (EXPECT_NOT(rem == 0))  return NO;
		
		do
		{
			char c = *str++;
			if (EXPECT('0' <= c && c <= '9'))
			{
				result = result * 10 + c - '0';
			}
			else
			{
				return NO;
			}
		}
		while (--rem);
		
		*outNatural = result;
		return YES;
	}
	
	return NO;
}


- (BOOL) getReal:(float *)outReal
{
	NSParameterAssert(outReal != NULL);
	
	if (_state.tokenType == kOOMeshTokenNatural || _state.tokenType == kOOMeshTokenReal)
	{
		//	Make null-terminated copy of token on stack and strtod() it.
		char buffer[_state.tokenLength + 1];
		memcpy(buffer, _state.cursor, _state.tokenLength);
		buffer[_state.tokenLength] = '\0';
		
		*outReal = strtod(buffer, NULL);
		return YES;
	}
	
	return NO;
}


- (BOOL) getString:(NSString **)outString
{
	NSParameterAssert(outString != NULL);
	
	if (_state.tokenType == kOOMeshTokenString ||
		_state.tokenType == kOOMeshTokenStringWithEscapes)
	{
		*outString = [self currentTokenString];
		return YES;
	}
	
	return NO;
}


- (BOOL) getKeywordOrString:(NSString **)outString
{
	NSParameterAssert(outString != NULL);
	
	if (_state.tokenType == kOOMeshTokenKeyword ||
		_state.tokenType == kOOMeshTokenString ||
		_state.tokenType == kOOMeshTokenStringWithEscapes)
	{
		*outString = [self currentTokenString];
		return YES;
	}
	
	return NO;
}


- (BOOL) getToken:(OOMeshTokenType)type
{
	return _state.tokenType == type;
}


- (BOOL) consumeNatural:(uint64_t *)outNatural
{
	return [self advance] && [self getNatural:outNatural];
}


- (BOOL) consumeReal:(float *)outReal
{
	return [self advance] && [self getReal:outReal];
}


- (BOOL) consumeString:(NSString **)outString
{
	return [self advance] && [self getString:outString];
}


- (BOOL) consumeKeywordOrString:(NSString **)outString
{
	return [self advance] && [self getKeywordOrString:outString];
}


- (BOOL) consumeToken:(OOMeshTokenType)type
{
	return [self advance] && _state.tokenType == type;
}


- (BOOL) consumeOptionalNewlines
{
	do
	{
		if (EXPECT_NOT(![self advance]))  return NO;
	} while (_state.tokenType == kOOMeshTokenNewline);
	
	return YES;
}


- (BOOL) consumeCommaOrNewlines
{
	BOOL seenComma = NO;
	BOOL seenAnything = NO;
	
	for (;;)
	{
		[self advance];
		OOMeshTokenType token = _state.tokenType;
		if (token == kOOMeshTokenComma)
		{
			if (!seenComma)
			{
				seenComma = YES;
			}
			else
			{
				// Multiple commas.
				return NO;
			}

		}
		else if (token != kOOMeshTokenNewline)
		{
			// End; must have seen at least one comma or newline.
			return seenAnything;
		}
		
		seenAnything = YES;
	}
}


//	Tokenizer core.
typedef struct OOMeshLexerState OOMeshLexerState;

OOINLINE BOOL IsDigit(uint8_t c)  INLINE_CONST_FUNC;
OOINLINE BOOL IsSign(uint8_t c)  INLINE_CONST_FUNC;
OOINLINE BOOL IsDigitOrSign(uint8_t c)  INLINE_CONST_FUNC;
OOINLINE BOOL IsWhitespace(uint8_t c)  INLINE_CONST_FUNC;
static BOOL IsAtNewline(OOMeshLexerState *state, const uint8_t *where);
OOINLINE BOOL IsCursorAtNewline(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;

OOINLINE BOOL ConsumeWhitespaceAndComments(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;

OOINLINE BOOL ScanBase(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;

OOINLINE BOOL ScanNumber(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;
OOINLINE BOOL ScanKeyword(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;
OOINLINE BOOL ScanString(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;
OOINLINE BOOL ScanOneCharToken(OOMeshLexerState *state, OOMeshTokenType type)  ALWAYS_INLINE_FUNC;
OOINLINE BOOL ScanNewline(OOMeshLexerState *state)  ALWAYS_INLINE_FUNC;


/*
	Style note: since the data is required to be UTF-8, rather than the
	“execution character set”, all character codes are explicit numbers.
*/
enum
{
	kCharSpace			= 0x20,
	kCharQuote			= 0x22,	// "
	kCharTab			= 0x09,
	kCharLF				= 0x0A,
	kCharCR				= 0x0D,
	kCharPlus			= 0x2B,	// +
	kCharComma			= 0x2C,	// ,
	kCharMinus			= 0x2D,	// -
	kCharDot			= 0x2E,	// .
	kCharForwardSlash	= 0x2F,	// /
	kCharColon			= 0x3A,	// :
	kCharOpenBracket	= 0x5B,	// [
	kCharBackslash		= 0x5C,	// "\"
	kCharCloseBracket	= 0x5D,	// ]
	kCharUnderscore		= 0x5F,	// _
	kCharOpenBrace		= 0x7B,	// {
	kCharCloseBrace		= 0x7D,	// }
	
	kCharDigit0			= 0x30,	// 0
	kCharDigit9			= 0x39,	// 9
	
	kCharUpperA			= 0x41,	// A
	kCharUpperZ			= 0x5A,	// Z
	
	kCharLowerA			= 0x61,	// a
	kCharLowerZ			= 0x7A,	// z
	
	// Escape codes.
	kCharLowerB			= 0x62,	// b
	kCharLowerF			= 0x66,	// f
	kCharLowerN			= 0x6E,	// n
	kCharLowerR			= 0x72,	// r
	kCharLowerT			= 0x74,	// t
	kCharLowerV			= 0x76,	// v
	
	//	U+2028 LINE SEPARATOR = E2, 80, A8
	//	U+2029 PARAGRAPH SEPARATOR = E2, 80, A9
	kCharLSPSByte1		= 0xE2,
	kCharLSPSByte2		= 0x80,
	kCharLSByte3		= 0xA8,
	kCharPSByte3		= 0xA9
};


OOINLINE BOOL IsDigit(uint8_t c)
{
	return kCharDigit0 <= c && c <= kCharDigit9;
}


OOINLINE BOOL IsSign(uint8_t c)
{
	return c == kCharPlus || c == kCharMinus;
}


OOINLINE BOOL IsDigitOrSign(uint8_t c)
{
	return IsDigit(c) || IsSign(c);
}


OOINLINE BOOL IsWhitespace(uint8_t c)
{
	return c == kCharSpace || c == kCharTab;
}


/*	keyword = keyword initial, { keyword char }
	keyword inital = alpha | "_"
	keyword char = keyword initial | digit | "." | "-"
*/
OOINLINE BOOL IsAlpha(uint8_t c)
{
	return (kCharUpperA <= c && c <= kCharUpperZ) || (kCharLowerA <= c && c <= kCharLowerZ);
}


OOINLINE BOOL IsKeywordInitial(uint8_t c)
{
	return IsAlpha(c) || c == kCharUnderscore;
}


OOINLINE BOOL IsKeywordChar(uint8_t c)
{
	return IsKeywordInitial(c) || IsDigit(c) || c == kCharDot || c == kCharMinus;
}


static BOOL IsAtNewline(OOMeshLexerState *state, const uint8_t *where)
{
	/*	Matches any of the following:
		U+000A LF
		U+000D CR
		U+2028 LINE SEPARATOR
		U+2029 PARAGRAPH SEPARATOR
		
		Note that data is required to be UTF-8.
		
		We check for LS and PS since they are the recommended newlines to be
		generated by new applications (not that many do). We don’t check for
		NEL, VT or FF (as suggested by UAX 13) because we aren’t dealing with
		arbitrary legacy text.
	*/
	
	uint8_t c = *where;
	if (c == kCharLF || c == kCharCR)  return YES;
	
	if (EXPECT((where + 3) < state->end))
	{
		if (c == kCharLSPSByte1 && where[1] == kCharLSPSByte2)
		{
			c = where[2];
			return c == kCharLSByte3 || c == kCharPSByte3;
		}
	}
	
	return NO;
}


OOINLINE BOOL IsCursorAtNewline(OOMeshLexerState *state)
{
	return IsAtNewline(state, state->cursor);
}


OOINLINE BOOL CommentStarts(OOMeshLexerState *state)
{
	return (state->cursor + 1) < state->end &&
			state->cursor[0] == kCharForwardSlash &&
			state->cursor[1] == kCharForwardSlash;
}


#define EOF_BREAK()  do { if (EXPECT_NOT(state->cursor == state->end))  return NO; } while (0)

OOINLINE BOOL ConsumeWhitespaceAndComments(OOMeshLexerState *state)
{
	for (;;)
	{
		EOF_BREAK();
		
		if (IsWhitespace(*state->cursor))  state->cursor++;
		else if (!CommentStarts(state))
		{
			return YES;
		}
		else
		{
			while (!IsCursorAtNewline(state))  state->cursor++;
			// Stops at the newline, which may be semantically significant.
		}
	}
}


/*	ScanFoo()
	These functions find the end of a range of characters that belong to a
	particular token class. They don’t do any parsing.
	
	They are force-inlined because they are each only called at one point.
*/
OOINLINE BOOL ScanNumber(OOMeshLexerState *state)
{
	NSCParameterAssert(state->cursor < state->end && IsDigitOrSign(*state->cursor));
	
	const uint8_t *loc = state->cursor;
	size_t remaining = state->end - loc;
	BOOL negative = NO;
	BOOL seenDot = NO;
	BOOL lastIsDot = NO;
	
	if (IsSign(*loc))
	{
		if (*loc == kCharMinus)  negative = YES;
		loc++;
		remaining--;
		if (remaining == 0)
		{
			state->tokenLength = 1;
			return NO;
		}
	}
	
	do
	{
		if (IsDigit(*loc))
		{
			lastIsDot = NO;
		}
		else
		{
			if (seenDot || *loc != kCharDot)
			{
				break;
			}
			else
			{
				seenDot = YES;
				lastIsDot = YES;
			}
		}
		loc++;
	}  while(--remaining);
	
	state->tokenLength = loc - state->cursor;
	if (!lastIsDot)
	{
		if (seenDot || negative)  state->tokenType = kOOMeshTokenReal;
		else  state->tokenType = kOOMeshTokenNatural;
		
		return YES;
	}
	
	return NO;
}


OOINLINE BOOL ScanKeyword(OOMeshLexerState *state)
{
	NSCParameterAssert(state->cursor < state->end && IsKeywordInitial(*state->cursor));
	
	const uint8_t *start = state->cursor;
	size_t remaining = state->end - start;
	size_t length = 0;
	
	do
	{
		length++;
	} while (IsKeywordChar(start[length]) && length < remaining);
	
	state->tokenType = kOOMeshTokenKeyword;
	state->tokenLength = length;
	return YES;
}


OOINLINE BOOL ScanString(OOMeshLexerState *state)
{
	NSCParameterAssert(state->cursor < state->end && *state->cursor == kCharQuote);
	
	const uint8_t *start = state->cursor;
	BOOL escapes = NO;
	
	state->cursor++;
	for (;;)
	{
		if (EXPECT_NOT(state->cursor == state->end))  goto UNEXPECTED_EOF;
		
		uint8_t c = *state->cursor;
		if (c == kCharQuote)  break;
		if (c == kCharBackslash)
		{
			state->cursor++;	// Skip over escape.
			if (EXPECT_NOT(state->cursor == state->end))  goto UNEXPECTED_EOF;
			
			escapes = YES;
		}
		
		// N.b.: this will handle backslash-newline combos as well.
		if (IsCursorAtNewline(state))
		{
			state->lineNumber++;
			if (state->cursor < state->end && *state->cursor == kCharLF)
			{
				// Skip over CRLF to avoid counting twice.
				state->cursor++;
			}
		}
		
		state->cursor++;
	}
	
	state->tokenLength = state->cursor - start + 1;
	state->cursor = start;
	state->tokenType = escapes ? kOOMeshTokenStringWithEscapes : kOOMeshTokenString;
	return YES;
	
UNEXPECTED_EOF:
	// EOF in string.
	state->tokenLength = state->end - state->cursor;
	return NO;
}


OOINLINE BOOL ScanOneCharToken(OOMeshLexerState *state, OOMeshTokenType type)
{
	NSCParameterAssert(state->cursor < state->end);
	
	state->tokenType = type;
	state->tokenLength = 1;
	return YES;
}


OOINLINE BOOL ScanNewline(OOMeshLexerState *state)
{
	NSCParameterAssert(IsCursorAtNewline(state));
	
	if (state->cursor + 1 < state->end && state->cursor[1] == kCharLF)
	{
		// Handle CRLF to avoid counting twice.
		state->tokenLength = 2;
	}
	else
	{
		state->tokenLength = 1;
	}
	
	state->lineNumber++;
	state->tokenType = kOOMeshTokenNewline;
	return YES;
}


OOINLINE BOOL ScanBase(OOMeshLexerState *state)
{
	// Skip to end of current token.
	state->cursor += state->tokenLength;
	state->tokenType = kOOMeshTokenInvalid;
	state->tokenLength = 0;
	NSCAssert(state->cursor <= state->end, @"OOMesh lexer passed end of buffer");
	
	if (state->cursor != state->end) {} else
	{
		state->tokenType = kOOMeshTokenEOF;
		return YES;
	}
	
	// Find beginning of next token.
	if (EXPECT_NOT(!ConsumeWhitespaceAndComments(state)))  return NO;
	EOF_BREAK();
	
	uint8_t c = *state->cursor;
	if (IsDigitOrSign(c))  return ScanNumber(state);
	if (IsKeywordInitial(c))  return ScanKeyword(state);
	if (c == kCharQuote)  return ScanString(state);
	
	// Handle single-character tokens.
	switch (c)
	{
		case kCharColon:  return ScanOneCharToken(state, kOOMeshTokenColon);
		case kCharComma:  return ScanOneCharToken(state, kOOMeshTokenComma);
		case kCharOpenBrace:  return ScanOneCharToken(state, kOOMeshTokenOpenBrace);
		case kCharCloseBrace:  return ScanOneCharToken(state, kOOMeshTokenCloseBrace);
		case kCharOpenBracket:  return ScanOneCharToken(state, kOOMeshTokenOpenBracket);
		case kCharCloseBracket:  return ScanOneCharToken(state, kOOMeshTokenCloseBracket);
	}
	
	if (IsCursorAtNewline(state))  return ScanNewline(state);
	
	return NO;
}


- (BOOL) advance
{
	DESTROY(_tokenString);
	return ScanBase(&_state);
}


- (NSString *) decodeEscapedString
{
	size_t idx = 0, spanStart = 0, size = _state.tokenLength - 2;
	NSMutableString *result = [NSMutableString stringWithCapacity:size];
	const uint8_t *buffer = _state.cursor + 1;
	
	while (idx < size)
	{
		if (buffer[idx] == kCharBackslash)
		{
			if (idx != spanStart)
			{
				NSString *fragment = [[NSString alloc] initWithBytes:buffer + spanStart
															  length:idx - spanStart
															encoding:NSUTF8StringEncoding];
				[result appendString:fragment];
				[fragment release];
			}
			
			// Ensuring this is ScanString's responsibility:
			NSAssert(idx + 2 <= size, @"Should not be able to run out of string in the middle of an escape code.");
			
			// Skip the backslash.
			idx++;
			
			// Substitution cases.
			if (buffer[idx] == kCharLowerR)
			{
				[result appendString:@"\r"];
				idx++;
			}
			else if (buffer[idx] == kCharLowerN)
			{
				[result appendString:@"\n"];
				idx++;
			}
			else if (buffer[idx] == kCharLowerT)
			{
				[result appendString:@"\t"];
				idx++;
			}
			else if (buffer[idx] == kCharBackslash)
			{
				[result appendString:@"\\"];
				idx++;
			}
			else if (buffer[idx] == kCharLowerV)
			{
				[result appendString:@"\v"];
				idx++;
			}
			else if (buffer[idx] == kCharLowerF)
			{
				[result appendString:@"\f"];
				idx++;
			}
			else if (buffer[idx] == kCharLowerB)
			{
				[result appendString:@"\b"];
				idx++;
			}
			else if (IsAtNewline(&_state, buffer + idx))
			{
				// Backslash-newline is simply skipped.
				if (idx + 1 < size && buffer[idx] == kCharCR && buffer[idx + 1] == kCharLF)
				{
					idx++;
				}
				idx++;
			}
			
			// For anything else, including \" and \', we just skip the backslash.
			
			spanStart = idx;
		}
		
		idx++;
	}
	
	if (idx != spanStart)
	{
		NSString *fragment = [[NSString alloc] initWithBytes:buffer + spanStart
													  length:idx - spanStart
													encoding:NSUTF8StringEncoding];
		[result appendString:fragment];
		[fragment release];
	}
	
	return result;
}

@end
