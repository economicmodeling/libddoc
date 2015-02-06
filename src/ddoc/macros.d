/**
 * Functions to work with DDOC macros.
 *
 * Provide functionalities to perform various macro-related operations, including:
 * - Expand a text, with $(D expand).
 * - Expand a macro, with $(D expandMacro);
 * - Parse macro files (.ddoc), with $(D parseMacrosFile);
 * - Parse a "Macros:" section, with $(D parseKeyValuePair);
 * To work with embedded documentation ('.dd' files), see $(D ddoc.standalone).
 *
 * Most functions provide two interfaces. One takes an $(D OutputRange) to write to,
 * and the other one is a convenience wrapper around it, which returns a string.
 * It uses an $(D std.array.Appender) as the output range.
 *
 * Most functions take a 'macros' parameter. The user is not required to pass
 * the standard D macros in it if he wants HTML output, the same macros that
 * are hardwired into DDOC are hardwired into libddoc (B, I, D_CODE, etc...).
 *
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott, Mathias 'Geod24' Lang
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */
module ddoc.macros;

///
unittest {
	import std.format : text;
	import ddoc.lexer;

	// Ddoc has some hardwired macros, which will be automatically searched.
	// List here: dlang.org/ddoc.html
	auto l1 = Lexer(`A simple $(B Hello $(I world))`);
	auto r1 = expand(l1, null);
	assert(r1 == `A simple <b>Hello <i>world</i></b>`, r1);

	// Example on how to parse ddoc file / macros sections.
	KeyValuePair[] pairs;
	auto lm2 = Lexer(`GREETINGS  =  Hello $(B $0)
			  IDENTITY = $0`);
	// Acts as we are parsing a ddoc file.
	assert(parseKeyValuePair(lm2, pairs));
	// parseKeyValuePair parses up to the first invalid token, or until
	// a section is reached. It returns false on parsing failure.
	assert(lm2.empty, lm2.front.text);
	assert(pairs.length == 2, text("Expected length 2, got: ", pairs.length));
	string[string] m2;
	foreach (kv; pairs)
		m2[kv[0]] = kv[1];
	// Macros are not expanded until the final call site.
	// This allow for forward reference of macro and recursive macros.
	assert(m2.get(`GREETINGS`, null) == `Hello $(B $0)`, m2.get(`GREETINGS`, null));
	assert(m2.get(`IDENTITY`, null) == `$0`, m2.get(`IDENTITY`, null));

	// There are some more specialized functions in this module, such as
	// expandMacro which expects the lexer to be placed on a macro, and
	// will consume the input (unlike expand, which exhaust a copy).
	auto l2 = Lexer(`$(GREETINGS $(IDENTITY John Doe))`);
	auto r2 = expand(l2, m2);
	assert(r2 == `Hello <b>John Doe</b>`, r2);

	// Note that the expansions are not processed recursively.
	// Hence, it's possible to have DDOC-formatted code inside DDOC.
	auto l3 = Lexer(`This $(DOLLAR)(MACRO) do not expand recursively.`);
	auto r3 = expand(l3, null);
	auto e3 = `This $(MACRO) do not expand recursively.`;
	assert(e3 == r3, r3);

	// The code can contains embedded code, which will be highlighted by
	// macros substitution (see corresponding DDOC macros).
	// The substitution is *NOT* performed by DDOC, and must be done by
	// calling $(D parseEmbedded) first.
	// If you forget to do so, libddoc will consider this as a developper
	// mistake, and will kindly inform you with an assertion error.
	auto s4 = `Here is some embedded D code I'd like to show you:
$(MY_D_CODE
------
void main() {
  import std.stdio : writeln;
  writeln("Hello,", " ", "world", "!");
}
------
)
Isn't it pretty ?`;
	auto l4 = Lexer(parseEmbedded(s4));
	// Embedded code is surrounded by D_CODE macro, and tokens have their own
	// macros (see: TODO).
	auto r4 = expand(l4, [ "MY_D_CODE": "<code>$1</code>", "D_CODE": "$0" ]);
	auto e4 = `Here is some embedded D code I'd like to show you:
<code>void main() {
  import std.stdio : writeln;
  writeln("Hello,", " ", "world", "!");
}
</code>
Isn't it pretty ?`;
	assert(r4 == e4, r4);
}

import ddoc.lexer;
import std.exception;
import std.range;
import std.algorithm;
import std.stdio;

alias KeyValuePair = Tuple!(string, string);

/// The set of ddoc's predefined macros.
immutable string[string] DEFAULT_MACROS;

shared static this()
{
	DEFAULT_MACROS =
		[
		 `B`: `<b>$0</b>`,
		 `I`: `<i>$0</i>`,
		 `U`: `<u>$0</u>`,
		 `P` : `<p>$0</p>`,
		 `DL` : `<dl>$0</dl>`,
		 `DT` : `<dt>$0</dt>`,
		 `DD` : `<dd>$0</dd>`,
		 `TABLE` : `<table>$0</table>`,
		 `TR` : `<tr>$0</tr>`,
		 `TH` : `<th>$0</th>`,
		 `TD` : `<td>$0</td>`,
		 `OL` : `<ol>$0</ol>`,
		 `UL` : `<ul>$0</ul>`,
		 `LI` : `<li>$0</li>`,
		 `LINK` : `<a href="$0">$0</a>`,
		 `LINK2` : `<a href="$1">$+</a>`,
		 `LPAREN` : `(`,
		 `RPAREN` : `)`,
		 `DOLLAR` : `$`,
		 `BACKTICK` : "`",
		 `DEPRECATED` : `$0`,

		 `RED` :   `<font color=red>$0</font>`,
		 `BLUE` :  `<font color=blue>$0</font>`,
		 `GREEN` : `<font color=green>$0</font>`,
		 `YELLOW` : `<font color=yellow>$0</font>`,
		 `BLACK` : `<font color=black>$0</font>`,
		 `WHITE` : `<font color=white>$0</font>`,

		 `D_CODE` : `<pre class="d_code">$0</pre>`,
		 `D_INLINECODE` : `<pre style="display:inline;" class="d_inline_code">$0</pre>`,
		 `D_COMMENT` : `$(GREEN $0)`,
		 `D_STRING`  : `$(RED $0)`,
		 `D_KEYWORD` : `$(BLUE $0)`,
		 `D_PSYMBOL` : `$(U $0)`,
		 `D_PARAM` : `$(I $0)`,

		 `DDOC` : `<html>
  <head>
    <META http-equiv="content-type" content="text/html; charset=utf-8">
    <title>$(TITLE)</title>
  </head>
  <body>
  <h1>$(TITLE)</h1>
  $(BODY)
  <hr>$(SMALL Page generated by $(LINK2 https://github.com/economicmodeling/libddoc, libddoc). $(COPYRIGHT))
  </body>
</html>`,

		 `DDOC_BACKQUOTED` : `$(D_INLINECODE $0)`,
		 `DDOC_COMMENT` : `<!-- $0 -->`,
		 `DDOC_DECL` : `$(DT $(BIG $0))`,
		 `DDOC_DECL_DD` : `$(DD $0)`,
		 `DDOC_DITTO` : `$(BR)$0`,
		 `DDOC_SECTIONS` : `$0`,
		 `DDOC_SUMMARY` : `$0$(BR)$(BR)`,
		 `DDOC_DESCRIPTION` : `$0$(BR)$(BR)`,
		 `DDOC_AUTHORS` : "$(B Authors:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_BUGS` : "$(RED BUGS:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_COPYRIGHT` : "$(B Copyright:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_DATE` : "$(B Date:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_DEPRECATED` : "$(RED Deprecated:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_EXAMPLES` : "$(B Examples:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_HISTORY` : "$(B History:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_LICENSE` : "$(B License:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_RETURNS` : "$(B Returns:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_SEE_ALSO` : "$(B See Also:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_STANDARDS` : "$(B Standards:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_THROWS` : "$(B Throws:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_VERSION` : "$(B Version:)$(BR)\n$0$(BR)$(BR)",
		 `DDOC_SECTION_H` : `$(B $0)$(BR)$(BR)`,
		 `DDOC_SECTION` : `$0$(BR)$(BR)`,
		 `DDOC_MEMBERS` : `$(DL $0)`,
		 `DDOC_MODULE_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_CLASS_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_STRUCT_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_ENUM_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_TEMPLATE_MEMBERS` : `$(DDOC_MEMBERS $0)`,
		 `DDOC_ENUM_BASETYPE` : `$0`,
		 `DDOC_PARAMS` : "$(B Params:)$(BR)\n$(TABLE $0)$(BR)",
		 `DDOC_PARAM_ROW` : `$(TR $0)`,
		 `DDOC_PARAM_ID` : `$(TD $0)`,
		 `DDOC_PARAM_DESC` : `$(TD $0)`,
		 `DDOC_BLANKLINE` : `$(BR)$(BR)`,

		 `DDOC_ANCHOR` : `<a name="$1"></a>`,
		 `DDOC_PSYMBOL` : `$(U $0)`,
		 `DDOC_PSUPER_SYMBOL` : `$(U $0)`,
		 `DDOC_KEYWORD` : `$(B $0)`,
		 `DDOC_PARAM` : `$(I $0)`,

		 `ESCAPES` : `/</&lt;/
/>/&gt;/
&/&amp;/`,
		 ];
}

/**
 * Write the text from the lexer to the $(D OutputRange), and expand any macro in it..
 *
 * expand takes a $(D ddoc.Lexer), and will, until it's empty, write it's expanded version to $(D output).
 *
 * Params:
 * input = A reference to the lexer to use. When expandMacros successfully returns, it will be empty.
 * macros = A list of DDOC macros to use for expansion. This override the previous definitions, hardwired in
 *		DDOC. Which means if an user provides a macro such as $(D macros["B"] = "<h1>$0</h1>";),
 *		it will be used, otherwise the default $(D macros["B"] = "<b>$0</b>";) will be used.
 *		To undefine hardwired macros, just set them to an empty string: $(D macros["B"] = "";).
 * output = An object satisfying $(D std.range.isOutputRange), usually a $(D std.array.Appender).
 */
void expand(O)(Lexer input, in string[string] macros, O output) if (isOutputRange!(O, string)) {
	// First, we need to turn every embedded code into a $(D_CODE)
	while (!input.empty) {
		assert(input.front.type != Type.embedded,
		       "You should call parseEmbedded first");
		if (input.front.type == Type.dollar) {
			input.popFront();
			if (input.front.type == Type.lParen) {
				auto mac = Lexer(matchParenthesis(input), true);
				if (!mac.empty)
					expandMacroImpl(mac, macros, output);
			} else
				output.put("$");
		} else {
			output.put(input.front.text);
			input.popFront();
		}
	}
 }

/// Ditto
string expand(Lexer input, string[string] macros) {
	import std.array : appender;
	auto app = appender!string();
	expand(input, macros, app);
	return app.data;
}

unittest {
	auto lex = Lexer(`Dat logo: $(LOGO dlang, Beautiful dlang logo)`);
	auto r = expand(lex, [ `LOGO` : `<img src="images/$1_logo.png" alt="$2">`]);
	auto exp = `Dat logo: <img src="images/dlang_logo.png" alt="Beautiful dlang logo">`;
	assert(r == exp, r);
}

/**
 * Expand a macro, and write the result to an $(D OutputRange).
 *
 * It's the responsability of the caller to ensure that the lexer contains the
 * beginning of a macro. The front of the input should be either a dollar
 * followed an opening parenthesis, or an opening parenthesis.
 *
 * If the macro does not have a closing parenthesis, input will be exhausted
 * and a $(D DdocException) will be thrown.
 *
 * Params:
 * input = A reference to a lexer with front pointing to the macro.
 * macros = Additional macros to use, in addition of DDOC's ones.
 * output = An $(D OutputRange) to write to.
 */
void expandMacro(O)(ref Lexer input, in string[string] macros, O output) if (isOutputRange!(O, string)) in {
		import std.format : text;
		assert(input.front.type == Type.dollar
		       || input.front.type == Type.lParen,
		       text("$ or ( expected, not ", input.front.type));
} body {
	import std.format : text;

	if (input.front.type == Type.dollar)
		input.popFront();
	assert(input.front.type == Type.lParen, text(input.front.type));
	auto l = Lexer(matchParenthesis(input), true);
	expandMacroImpl(l, macros, output);
 }

/// Ditto
string expandMacro(ref Lexer input, in string[string] macros) in {
	import std.format : text;
	assert(input.front.type == Type.dollar
	       || input.front.type == Type.lParen,
	       text("$ or ( expected, not ", input.front.type));
} body {
	import std.array : appender;
	auto app = appender!string();
	expandMacro(input, macros, app);
	return app.data;
}

///
unittest {
	import ddoc.lexer;
	import std.array : appender;

	auto macros =
		[
		 "IDENTITY": "$0",
		 "HWORLD": "$(IDENTITY Hello world!)",
		 "ARGS": "$(IDENTITY $1 $+)",
		 "GREETINGS": "$(IDENTITY $(ARGS Hello,$0))",
		 ];

	auto l1 = Lexer(`$(HWORLD)`);
	auto r1 = expandMacro(l1, macros);
	assert(r1 == "Hello world!", r1);

	auto l2 = Lexer(`$(B $(IDENTITY $(GREETINGS John Malkovich)))`);
	auto r2 = expandMacro(l2, macros);
	assert(r2 == "<b>Hello John Malkovich</b>", r2);

	// Macros that have should take args but don't get them expand to empty string.
	auto l3 = Lexer(`$(GREETINGS)`);
	auto r3 = expandMacro(l3, macros);
	//assert(r3 == "", r3);
}

/// A simple example, with recursive macros:
unittest {
	import ddoc.lexer;

	auto lex = Lexer(`$(MYTEST Un,jour,mon,prince,viendra)`);
	auto macros = [ `MYTEST`: `$1 $(MYTEST $+)` ];
	// Note: There's also a version of expand that takes an OutputRange.
	auto result = expand(lex, macros);
	assert(result == `Un jour mon prince viendra `, result);
}

unittest {
	import std.array;
	auto macros =
		[
		 "D" : "<b>$0</b>",
		 "P" : "<p>$(D $0)</p>",
		 "KP" : "<b>$1</b><i>$+</i>",
		 "LREF" : `<a href="#$1">$(D $1)</a>`
		 ];
	auto l = Lexer(`$(D something $(KP a, b) $(P else), abcd) $(LREF byLineAsync)`c);
	auto expected = `<b>something <b>a</b><i>b</i> <p><b>else</b></p>, abcd</b> <a href="#byLineAsync"><b>byLineAsync</b></a>`;
	auto result = appender!string();
	expand(l, macros, result);
	assert (result.data == expected, result.data);
	// writeln(result.data);
}

unittest {
	auto l1 = Lexer("Do you have a $(RPAREN) problem with $(LPAREN) me?");
	auto r1 = expand(l1, null);
	assert(r1 == "Do you have a ) problem with ( me?", r1);

	auto l2 = Lexer("And (with $(LPAREN) me) ?");
	auto r2 = expand(l2, null);
	assert(r2 == "And (with ( me) ?", r2);

	auto l3 = Lexer("What about $(TEST me) ?");
	auto r3 = expand(l3, [ "TEST": "($0" ]);
	assert(r3 == "What about (me ?", r3);
}

/**
 * Parse a string and replace embedded code (code between at least 3 '-') with
 * the relevant macros.
 *
 * Params:
 * str = A string that might contain embedded code. Only code will be modified.
 *
 * Returns:
 * A (possibly new) string containing the embedded code put in the proper macros.
 */
string parseEmbedded(string str) {
	auto lex = Lexer(str, true);
	auto output = appender!string;
	while (!lex.empty) {
		if (lex.front.type == Type.embedded) {
			output.put("$(D_CODE ");
			output.put(lex.front.text);
			output.put(")");
		}
		else
			output.put(lex.front.text);
		lex.popFront();
	}
	return output.data;
}

/**
 * Parses macros files, usually with extension .ddoc.
 *
 * Macros files are files that only contains macros definitions.
 * Newline after a macro is part of this macro, so a blank line between
 * macro A and macro B will lead to macro A having a trailing newline.
 * If you wish to split your file in blocks, terminate each block with
 * a dummy macro, e.g: '_' (underscore).
 *
 * Params:
 * paths = A variadic array with paths to ddoc files.
 *
 * Returns:
 * An associative array containing all the macros parsed from the files.
 * In case of multiple definitions, macros are overriden.
 */
string[string] parseMacrosFile(R)(R paths) if (isInputRange!(R)) {
	import std.exception : enforceEx;
	import std.file : readText;
	import std.format : text;

	string[string] ret;
	foreach (file; paths) {
		KeyValuePair[] pairs;
		auto txt = readText(file);
		auto lexer = Lexer(txt, true);
		parseKeyValuePair(lexer, pairs);
		enforceEx!DdocException(lexer.empty, text("Unparsed data (", lexer.offset, "): ", lexer.text[lexer.offset..$]));
		foreach (kv; pairs)
			ret[kv[0]] = kv[1];
	}
	return ret;
}

/**
 * Parses macros (or params) declaration list until the lexer is empty.
 *
 * Macros are simple Key/Value pair. So, a macro is declared as: NAME=VALUE.
 * Any number of whitespace (space / tab) can precede and follow the equal sign.
 *
 * Params:
 * lexer = A reference to lexer consisting solely of macros definition (if $(D stopAtSection) is false),
 *	   or consisting of a macro followed by other sections.
 *	   Consequently, at the end of the parsing, the lexer will be empty or may point to a section.
 * pairs = A reference to an array of $(D KeyValuePair), where the macros will be stored.
 *
 * Returns: true if the parsing succeeded.
 */
bool parseKeyValuePair(ref Lexer lexer, ref KeyValuePair[] pairs) {
	import std.array : appender;
	import std.format : text;
	string prevKey, key;
	string prevValue, value;
	while (!lexer.empty) {
		// If parseAsKeyValuePair returns true, we stopped on a newline.
		// If it returns false, we're either on a section (header),
		// or the continuation of a macro.
		if (!parseAsKeyValuePair(lexer, key, value)) {
			if (prevKey == null) // First pass and invalid data
				return false;
			if (lexer.front.type == Type.header)
				break;
			assert(lexer.offset >= prevValue.length);
			size_t start = tokOffset(lexer)	- prevValue.length;
			while (!lexer.empty && lexer.front.type != Type.newline) {
				lexer.popFront();
			}
			prevValue = lexer.text[start..lexer.offset];
		} else {
			// New macro, we can save the previous one.
			// The only case when key would not be defined is on first pass.
			if (prevKey)
				pairs ~= KeyValuePair(prevKey, prevValue);
			prevKey = key;
			prevValue = value;
			key = value = null;
		}
		if (!lexer.empty) {
			assert(lexer.front.type == Type.newline,
			       text("Front: ", lexer.front.type, ", text: ", lexer.text[lexer.offset..$]));
			lexer.popFront();
		}
	}

	if (prevKey)
		pairs ~= KeyValuePair(prevKey, prevValue);

	return true;
}

private:
// upperArgs is a string[11] actually, or null.
void expandMacroImpl(O)(Lexer input, in string[string] macros, O output) {
	import std.format : text;

	//debug writeln("Expanding: ", input.text);
	// Check if the macro exist and get it's value.
	if (input.front.type != Type.word)
		return;
	string macroName = input.front.text;
	//debug writeln("[EXPAND] Macro name: ", input.front.text);
	string macroValue = lookup(macroName, macros);
	// No point loosing time if the macro is undefined.
	if (macroValue is null) return;
	//debug writeln("[EXPAND] Macro value: ", macroValue);
	input.popFront();

	// Special case for $(DDOC). It's ugly, but it gets the job done.
	if (input.empty && macroName == "BODY") {
		output.put(lookup("BODY", macros));
		return;
	}
	input.popFront();

	// Collect the arguments
	if (!input.empty && (input.front.type == Type.whitespace || input.front.type == Type.newline))
		input.popFront();
	string[11] arguments;
	auto c = collectMacroArguments(input, arguments);
	//debug writeln("[EXPAND] There are ", c, " arguments");

	// First pass
	auto argOutput = appender!string();
	if (!replaceArgs(macroValue, arguments, argOutput))
		return;

	// Second pass
	replaceMacs(argOutput.data, macros, output);
}

unittest {
	auto a1 = appender!string();
	expandMacroImpl(Lexer(`B value`), null, a1);
	assert(a1.data == `<b>value</b>`, a1.data);

	auto a2 = appender!string();
	expandMacroImpl(Lexer(`IDENTITY $(B value)`), [ "IDENTITY": "$0" ], a2);
	assert(a2.data == `<b>value</b>`, a2.data);
}

// Try to parse a line as a KeyValuePair, returns false if it fails
private bool parseAsKeyValuePair(ref Lexer olexer, ref string key, ref string value) {
	string _key;
	auto lexer = olexer;
	while (!lexer.empty && (lexer.front.type == Type.whitespace
				|| lexer.front.type == Type.newline))
		lexer.popFront();
	if (!lexer.empty && lexer.front.type == Type.word) {
		_key = lexer.front.text;
		lexer.popFront();
	} else
		return false;
	while (!lexer.empty && lexer.front.type == Type.whitespace)
		lexer.popFront();
	if (!lexer.empty && lexer.front.type == Type.equals)
		lexer.popFront();
	else
		return false;
	while (lexer.front.type == Type.whitespace)
		lexer.popFront();
	assert(lexer.offset > 0, "Something is wrong with the lexer");
	// Offset points to the END of the token, not the beginning.
	size_t start = tokOffset(lexer);
	while (!lexer.empty && lexer.front.type != Type.newline) {
		assert(lexer.front.type != Type.header);
		lexer.popFront();
	}
	olexer = lexer;
	key = _key;
	size_t end = lexer.offset - ((start != lexer.offset && lexer.offset != lexer.text.length) ? (1) : (0));
	value = lexer.text[start..end];
	return true;
}

// Note: For macro $(NAME arg1,arg2), collectMacroArguments receive "arg1,arg2".
size_t collectMacroArguments(Lexer input, ref string[11] args) {
	import std.format : text;

	size_t argPos = 1;
	size_t argStart = tokOffset(input);
	args[] = null;
	if (input.empty) return 0;
	args[0] = input.text[tokOffset(input) .. $];
	while (!input.empty) {
		assert(input.front.type != Type.embedded, "You should call parseEmbedded first");
		switch (input.front.type) {
		case Type.comma:
			if (argPos <= 9)
				args[argPos++] = input.text[argStart .. (input.offset - 1)];
			input.popFront();
			stripWhitespace(input);
			argStart = tokOffset(input);
			// Set the $+ parameter.
			if (argPos == 2)
				args[10] = input.text[tokOffset(input) .. $];
			break;
		case Type.lParen:
			// Advance the lexer to the matching parenthesis.
			auto err = input.text[input.offset..$];
			auto substr = matchParenthesis(input);
			break;
			// TODO: Implement ", ' and <-- pairing.
		default:
			input.popFront();
		}
	}
	assert(argPos >= 1 && argPos <= 10, text(argPos));
	if (argPos <= 9)
		args[argPos] = input.text[argStart .. input.offset];
	return argPos;
}

unittest {
	import std.format : text;
	string[11] args;

	auto l1 = Lexer(`Hello, world`);
	auto c1 = collectMacroArguments(l1, args);
	assert(c1 == 2, text(c1));
	assert(args[0] == `Hello, world`, args[0]);
	assert(args[1] == `Hello`, args[1]);
	assert(args[2] == `world`, args[2]);
	for (size_t i = 3; i < 10; ++i)
		assert(args[i] is null, args[i]);
	assert(args[10] == `world`, args[10]);

	auto l2 = Lexer(`goodbye,cruel,world,I,will,happily,return,home`);
	auto c2 = collectMacroArguments(l2, args);
	assert(c2 == 8, text(c2));
	assert(args[0] == `goodbye,cruel,world,I,will,happily,return,home`, args[0]);
	assert(args[1] == `goodbye`, args[1]);
	assert(args[2] == `cruel`, args[2]);
	assert(args[3] == `world`, args[3]);
	assert(args[4] == `I`, args[4]);
	assert(args[5] == `will`, args[5]);
	assert(args[6] == `happily`, args[6]);
	assert(args[7] == `return`, args[7]);
	assert(args[8] == `home`, args[8]);
	assert(args[9] is null, args[9]);
	assert(args[10] == `cruel,world,I,will,happily,return,home`, args[10]);

	// It's not as easy as a split !
	auto l3 = Lexer(`this,(is,(just,two),args)`);
	auto c3 = collectMacroArguments(l3, args);
	assert(c3 == 2, text(c3));
	assert(args[0] == `this,(is,(just,two),args)`, args[0]);
	assert(args[1] == `this`, args[1]);
	assert(args[2] == `(is,(just,two),args)`, args[2]);
	for (size_t i = 3; i < 10; ++i)
		assert(args[i] is null, args[i]);
	assert(args[10] == `(is,(just,two),args)`, args[10]);

	auto l4 = Lexer(``);
	auto c4 = collectMacroArguments(l4, args);
	assert(c4 == 0, text(c4));
	for (size_t i = 0; i < 11; ++i)
		assert(args[i] is null, args[i]);

	import std.string : split;
	enum first = `I,am,happy,to,join,with,you,today,in,what,will,go,down,in,history,as,the,greatest,demonstration,for,freedom,in,the,history,of,our,nation.`;
	auto l5 = Lexer(first);
	auto c5 = collectMacroArguments(l5, args);
	assert(c5 == 10, text(c5));
	assert(args[0] == first, args[0]);
	foreach (idx, word; first.split(",")[0..9])
		assert(args[idx+1] == word, text(word , " != ", args[idx+1]));
	assert(args[10] == first[2..$], args[10]);

	// TODO: ", ', {, <--, matched and unmatched.
}

// Where the grunt work is done...

bool replaceArgs(O)(string val, in string[11] args, O output) {
	import std.format : text;
	import std.ascii : isDigit;

	bool hasEnd;
	auto lex = Lexer(val, true);
	while (!lex.empty) {
		assert(lex.front.type != Type.embedded, "You should call parseEmbedded first");
		switch (lex.front.type) {
		case Type.dollar:
			lex.popFront();
			// It could be $1_test
			if (isDigit(lex.front.text[0])) {
				auto idx = lex.front.text[0] - '0';
				assert(idx >= 0 && idx <= 9, text(idx));
				// Missing argument
				if (args[idx] is null)
					return false;
				output.put(args[idx]);
				output.put(lex.front.text[1..$]);
				lex.popFront();
			} else if (lex.front.text == "+") {
				lex.popFront();
				output.put(args[10]);
			} else {
				output.put("$");
			}
			break;
		case Type.lParen:
			output.put("(");
			if (!replaceArgs(matchParenthesis(lex, &hasEnd), args, output))
				return false;
			if (hasEnd)
				output.put(")");
			break;
		default:
			output.put(lex.front.text);
			lex.popFront();
		}
	}
	return true;
}

unittest {
	string[11] args;

	auto a1 = appender!string;
	args[0] = "Some kind of test, I guess";
	args[1] = "Some kind of test";
	args[2] = " I guess";
	assert(replaceArgs("$(MY $(SUPER $(MACRO $0)))", args, a1));
	assert(a1.data == "$(MY $(SUPER $(MACRO Some kind of test, I guess)))",
	       a1.data);

	auto a2 = appender!string;
	args[] = null;
	args[0] = "Some,kind,of,test";
	args[1] = "Some";
	args[2] = "kind";
	args[3] = "of";
	args[4] = "test";
	args[10] = "kind,of,test";
	assert(replaceArgs("$(SOME $(MACRO $1 $+))", args, a2));
	assert(a2.data == "$(SOME $(MACRO Some kind,of,test))", a2.data);

	auto a3 = appender!string;
	args[] = null;
	args[0] = "Some,kind";
	args[1] = "Some";
	args[2] = "kind";
	args[10] = "kind";
	assert(!replaceArgs("$(SOME $(MACRO $1 $2 $3))", args, a3));
}

void replaceMacs(O)(string val, in string[string] macros, O output) {
	//debug writeln("[REPLACE] Arguments replaced: ", val);
	bool hasEnd;
	auto lex = Lexer(val, true);
	while (!lex.empty) {
		assert(lex.front.type != Type.embedded, "You should call parseEmbedded first");
		switch (lex.front.type) {
		case Type.dollar:
			lex.popFront();
			if (lex.front.type == Type.lParen)
				expandMacro(lex, macros, output);
			else
				output.put("$");
			break;
		case Type.lParen:
			output.put("(");
			auto par = matchParenthesis(lex, &hasEnd);
			expand(Lexer(par), macros, output);
			if (hasEnd)
				output.put(")");
			break;
		default:
			output.put(lex.front.text);
			lex.popFront();
		}
	}
}

// Some utilities functions

/**
 * Must be called with a parenthesis as the front item of $(D lexer).
 * Will move the lexer forward until a matching parenthesis is met,
 * taking nesting into account.
 * If no matching parenthesis is met, returns null (and $(D lexer) will be empty).
 */
string matchParenthesis(ref Lexer lexer, bool* hasEnd = null) in {
	import std.format : text;
	assert(lexer.front.type == Type.lParen, text(lexer.front));
	assert(lexer.offset);
} body {
	size_t count;
	size_t start = lexer.offset;
	do {
		if (lexer.front.type == Type.rParen)
			--count;
		else if (lexer.front.type == Type.lParen)
			++count;
		lexer.popFront();
	} while (count > 0 && !lexer.empty);
	size_t end = (lexer.empty) ? lexer.text.length : tokOffset(lexer);
	if (hasEnd !is null) *hasEnd = (count == 0);
	if (count == 0) end -= 1;
	return lexer.text[start .. end];
}

unittest {
	auto l1 = Lexer(`(Hello) World`);
	auto r1 = matchParenthesis(l1);
	assert(r1 == "Hello", r1);
	assert(!l1.empty);

	auto l2 = Lexer(`()`);
	auto r2 = matchParenthesis(l2);
	assert(r2 == "", r2);
	assert(l2.empty);

	auto l3 = Lexer(`(())`);
	auto r3 = matchParenthesis(l3);
	assert(r3 == "()", r3);
	assert(l3.empty);

	auto l4 = Lexer(`W (He(l)lo)`);
	l4.popFront(); l4.popFront();
	auto r4 = matchParenthesis(l4);
	assert(r4 == "He(l)lo", r4);
	assert(l4.empty);

	auto l5 = Lexer(` @(Hello())   ()`);
	l5.popFront(); l5.popFront();
	auto r5 = matchParenthesis(l5);
	assert(r5 == "Hello()", r5);
	assert(!l5.empty);

	auto l6 = Lexer(`(Hello()   (`);
	auto r6 = matchParenthesis(l6);
	assert(r6 == "Hello()   (", r6);
	assert(l6.empty);
}

size_t tokOffset(in Lexer lex) { return lex.offset - lex.front.text.length; }

unittest {
	import std.format : text;

	auto lex = Lexer(`My  (friend) $ lives abroad`);
	auto expected = [0, 2, 4, 5, 11, 12, 13, 14, 15, 20, 21];
	while (!lex.empty) {
		assert(expected.length > 0, "Test and results are not in sync");
		assert(tokOffset(lex) == expected[0], text(lex.front, " : ", tokOffset(lex), " -- ", expected[0]));
		lex.popFront();
		expected = expected[1..$];
	}
}

string lookup(in string name, in string[string] macros, string defVal = null) {
	auto p = name in macros;
	if (p is null)
		return DEFAULT_MACROS.get(name, defVal);
	return *p;
}

void stripWhitespace(ref Lexer lexer) {
	while (!lexer.empty && (lexer.front.type == Type.whitespace || lexer.front.type == Type.newline))
		lexer.popFront();
}
