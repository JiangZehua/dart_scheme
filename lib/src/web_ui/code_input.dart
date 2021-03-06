library web_ui.code_input;

import 'dart:async';
import 'dart:html';

import 'package:tuple/tuple.dart';

import 'package:cs61a_scheme/cs61a_scheme.dart';
import 'package:cs61a_scheme/cs61a_scheme_web.dart';

import 'highlight.dart';

const List<SchemeSymbol> noIndentForms = [
  SchemeSymbol("let"),
  SchemeSymbol("define"),
  SchemeSymbol("lambda"),
  SchemeSymbol("define-macro")
];

bool _isAutocompleteEnabled = false;

class CodeInput {
  Element element;
  Element _autoBox;
  Element _autoBoxWrapper;
  Map<String, Docs> wordToDocs;
  bool _active = true;
  final List<StreamSubscription> _subs = [];
  String tabComplete = "";

  Function(String code) runCode;
  Function(int parens) parenListener;

  CodeInput(Element log, this.runCode, this.wordToDocs, {this.parenListener}) {
    element = SpanElement()
      ..classes = ['code-input']
      ..contentEditable = 'true';
    _autoBox = DivElement()
      ..classes = ["docs"]
      ..style.visibility = "hidden";
    _autoBoxWrapper = DivElement()
      ..classes = ["render"]
      ..append(_autoBox);
    _subs.add(element.onKeyPress.listen(_onInputKeyPress));
    _subs.add(element.onKeyDown.listen(_keyListener));
    _subs.add(element.onKeyUp.listen(_keyListener));
    log.append(element);
    log.append(_autoBoxWrapper);
    element.focus();
    parenListener ??= (_) => null;
    parenListener(missingParens);
  }

  String get text => element.text;

  set text(String newText) {
    element.text = newText;
    highlight(atEnd: true);
  }

  bool get active => _active;

  int get missingParens => countParens(text);

  void deactivate() {
    _active = false;
    element.contentEditable = 'false';
    _autoBoxWrapper.remove();
    for (var sub in _subs) {
      sub.cancel();
    }
  }

  void enableAutocomplete() => _isAutocompleteEnabled = true;
  void disableAutocomplete() => _isAutocompleteEnabled = false;

  Future highlight(
      {bool saveCursor = false, int cursor, bool atEnd = false}) async {
    if (saveCursor) {
      await highlightSaveCursor(element);
    } else if (cursor != null) {
      await highlightCustomCursor(element, cursor);
    } else if (atEnd) {
      await highlightAtEnd(element, element.text);
    } else {
      element.innerHtml = highlightText(element.text);
    }
  }

  Future _onInputKeyPress(KeyboardEvent event) async {
    if ((missingParens ?? -1) > 0 &&
        event.shiftKey &&
        event.keyCode == KeyCode.ENTER) {
      event.preventDefault();
      element.text = element.text.trimRight() + ')' * missingParens + '\n';
      runCode(element.text);
      await delay(100);
      await highlight();
    } else if ((missingParens ?? -1) == 0 && event.keyCode == KeyCode.ENTER) {
      event.preventDefault();
      element.text = element.text.trimRight() + '\n';
      runCode(element.text);
      await delay(100);
      await highlight();
    } else if ((missingParens ?? 0) > 0 && KeyCode.ENTER == event.keyCode) {
      event.preventDefault();
      int cursor = findPosition(element, window.getSelection().getRangeAt(0));
      String newInput = element.text;
      String first = newInput.substring(0, cursor) + "\n";
      String second = "";
      if (cursor != newInput.length) {
        second = newInput.substring(cursor);
      }
      int spaces = _countSpace(newInput, cursor);
      element.text = first + " " * spaces + second;
      await highlight(cursor: cursor + spaces + 1);
    } else {
      await delay(5);
      await highlight(saveCursor: true);
    }
    parenListener(missingParens);
  }

  /// Determines the operation at the last open parens.
  ///
  /// Returns a two item list where the first item indicates the word that was matched
  /// and the second item indicates if that word is the full string (true)
  /// or is in progress of being written out (false).
  Tuple2<String, bool> _currOp(String inputText, int position,
      [int fromLast = 1]) {
    List<String> splitLines = inputText.substring(0, position).split("\n");
    bool isMultipleLines = false;
    String refLine;
    int totalMissingCount = 0;

    for (refLine in splitLines.reversed) {
      totalMissingCount += countParens(refLine) ?? 0;
      // Find the first line with an open paren but no close parentheses.
      if (totalMissingCount >= fromLast) break;
      isMultipleLines = true;
    }
    // If there are not enough open parentheses, return the default output value.
    if (totalMissingCount >= fromLast) {
      int strIndex = refLine.indexOf("(");
      while (strIndex != -1 && strIndex < (refLine.length - 1)) {
        int nextClose = refLine.indexOf(")", strIndex + 1);
        int nextOpen = refLine.indexOf("(", strIndex + 1);
        // Find the open parentheses that corresponds to the missing closed parentheses.
        if (totalMissingCount > fromLast) {
          totalMissingCount -= 1;
        } else if (nextOpen == -1 || nextClose == -1 || nextOpen < nextClose) {
          // Find the operations separated by any number of spaces, open parentheses, or closed parentheses.
          List splitRef =
              refLine.substring(strIndex + 1).split(RegExp("[ ()]+"));
          String op =
              splitRef.firstWhere((s) => s.isNotEmpty, orElse: () => "");
          return Tuple2(op,
              (splitRef.length - splitRef.indexOf(op)) > 1 || isMultipleLines);
        }
        strIndex = nextOpen;
      }
    }
    return const Tuple2("", true);
  }

  /// Determines how much space to indent the next line, based on parens.
  int _countSpace(String inputText, int position) {
    List<String> splitLines = inputText.substring(0, position).split("\n");
    // If the cursor is at the end of the line but not the end of the input, we
    // must find that line and start counting parens from there.
    String refLine;
    int totalMissingCount = 0;
    for (refLine in splitLines.reversed) {
      // Truncate to position of cursor when in middle of the line.
      totalMissingCount += countParens(refLine);
      // Find the first line with an open paren but no close paren.
      if (totalMissingCount >= 1) break;
    }
    if (totalMissingCount == 0) {
      return 0;
    }
    int strIndex = refLine.indexOf("(");
    while (strIndex < (refLine.length - 1)) {
      int nextClose = refLine.indexOf(")", strIndex + 1);
      int nextOpen = refLine.indexOf("(", strIndex + 1);
      // Find the open paren that corresponds to the missing closed paren.
      if (totalMissingCount > 1) {
        totalMissingCount -= 1;
      } else if (nextOpen == -1 || nextOpen < nextClose) {
        Iterable<Expression> tokens = tokenizeLine(refLine.substring(strIndex));
        Expression symbol = tokens.elementAt(1);
        // Align subexpressions if any exist; otherwise, indent by two spaces.
        if (symbol == const SchemeSymbol("(")) {
          return strIndex + 1;
        } else if (noIndentForms.contains(symbol)) {
          return strIndex + 2;
        } else if (tokens.length > 2) {
          return refLine.indexOf(tokens.elementAt(2).toString(), strIndex + 1);
        } else if (nextOpen == -1) {
          return strIndex + 2;
        }
      } else if (nextClose == -1) {
        return strIndex + 2;
      }
      strIndex = nextOpen;
    }
    return strIndex + 2;
  }

  /// Find the list of words that contain the same prefix as currWord.
  List<String> _wordMatches(String currWord, bool fullWord) {
    List<String> matchingWords = [];
    for (String schemeWord in wordToDocs.keys) {
      if (((schemeWord.length > currWord.length) && !fullWord) ||
          schemeWord.length == currWord.length) {
        if (schemeWord.substring(0, currWord.length) == currWord) {
          matchingWords.add(schemeWord);
        }
      }
    }
    return matchingWords;
  }

  /// Finds and displays the possible words that the user may be typing.
  void _autocomplete() {
    // Find the text to the left of where the typing cursor currently is.
    int cursorPos = findPosition(element, window.getSelection().getRangeAt(0));
    List<String> matchingWords = [];
    int currLength = 0;
    // Find the last word that being typed [output] or the second to last operation that was typed [output2].
    // Used for the case where an empty open parentheses is being typed.
    // Eventually, may be used to implement different autocomplete behavior for special forms.
    Tuple2<String, bool> output = _currOp(element.text, cursorPos);
    Tuple2<String, bool> secondToLastOutput =
        _currOp(element.text, cursorPos, 2);
    String match = output.item1;
    bool isFullWord = output.item2;
    if (match.isEmpty) {
      match = secondToLastOutput.item1;
      isFullWord = secondToLastOutput.item2;
    }
    if (match.isNotEmpty) {
      matchingWords = _wordMatches(match, isFullWord);
      currLength = match.length;
    }
    // Clear whatever is currently in the box.
    _autoBox.children = [];
    _autoBox.classes = ["docs"];
    if (matchingWords.isEmpty) {
      // If there are no matching words, hide the autocomplete box.
      tabComplete = "";
      _autoBox.style.visibility = "hidden";
    } else if (matchingWords.length == 1) {
      // If there is only one matching word, display the docs for that word.
      render(wordToDocs[matchingWords.first], _autoBox);
      _autoBox.style.visibility = "hidden";
      _autoBox.children.last.style.visibility = "visible";
      tabComplete = matchingWords.first.substring(currLength);
    } else {
      tabComplete = "";
      // Add each matching word as its own element for formatting purposes.
      for (String match in matchingWords) {
        _autoBox.append(SpanElement()
          ..classes = ["autobox-word"]
          // Bold the matching characters.
          ..innerHtml =
              "<strong>${match.substring(0, currLength)}</strong>${match.substring(currLength)}");
      }
      _autoBox.style.visibility = "visible";
    }
    _autoBox.scrollIntoView();
  }

  _keyListener(KeyboardEvent event) async {
    int key = event.keyCode;
    if (_isAutocompleteEnabled) {
      _autocomplete();
    }
    if (key == KeyCode.BACKSPACE) {
      await delay(0);
      parenListener(missingParens);
      await highlight(saveCursor: true);
    } else if (event.ctrlKey && (key == KeyCode.V || key == KeyCode.X)) {
      await delay(0);
      parenListener(missingParens);
      await highlight(saveCursor: true);
    } else if (key == KeyCode.TAB) {
      event.preventDefault();
      int cursor = findPosition(element, window.getSelection().getRangeAt(0));
      element.appendText(tabComplete);
      await highlight(cursor: cursor + tabComplete.length + 1);
    }
  }
}
