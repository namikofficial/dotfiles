const assert = require("assert");
const fs = require("fs");
const path = require("path");

// Extract the evaluateCalc logic into a testable JS function.
// This mirrors the QML implementation but runs in plain Node.js.
function evaluateCalc(expr) {
    if (!expr || expr.length === 0) return { valid: false, display: "?", value: "" };
    var ch, num = "", tokens = [];
    for (var i = 0; i < expr.length; i++) {
        ch = expr[i];
        if ((ch >= '0' && ch <= '9') || ch === '.') {
            num += ch;
            continue;
        }
        if (num) {
            var n = parseFloat(num);
            if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(num) || isNaN(n)) return { valid: false, display: "Invalid number", value: "" };
            tokens.push({ t: "num", v: n });
            num = "";
        }
        if (ch === ' ') continue;
        if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '(' || ch === ')' || ch === '%') {
            tokens.push({ t: ch, v: ch });
            continue;
        }
        return { valid: false, display: "Invalid character", value: "" };
    }
    if (num) {
        var n2 = parseFloat(num);
        if (!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(num) || isNaN(n2)) return { valid: false, display: "Invalid number", value: "" };
        tokens.push({ t: "num", v: n2 });
        num = "";
    }
    if (tokens.length === 0) return { valid: false, display: "?", value: "" };

    var pos = 0;
    function peek() { return pos < tokens.length ? tokens[pos] : null; }
    function consume() { return pos < tokens.length ? tokens[pos++] : null; }

    function parseExpr() {
        var left = parseTerm();
        while (peek() && (peek().t === '+' || peek().t === '-')) {
            var op = consume().v;
            var right = parseTerm();
            left = op === '+' ? left + right : left - right;
        }
        return left;
    }
    function parseTerm() {
        var left = parseFactor();
        while (peek() && (peek().t === '*' || peek().t === '/' || peek().t === '%')) {
            var op = consume().v;
            var right = parseFactor();
            if (op === '*') {
                left *= right;
            } else if (op === '/') {
                if (right === 0) throw new Error("div0");
                left /= right;
            } else {
                if (right === 0) throw new Error("mod0");
                left = left % right;
            }
        }
        return left;
    }
    function parseFactor() {
        if (peek() && peek().t === '-') {
            consume();
            return -parseFactor();
        }
        if (peek() && peek().t === '(') {
            consume();
            var val = parseExpr();
            if (!peek() || peek().t !== ')') throw new Error("unclosed");
            consume();
            return val;
        }
        var tok = consume();
        if (!tok || tok.t !== "num") throw new Error("bad");
        return tok.v;
    }

    try {
        var result = parseExpr();
        if (pos < tokens.length) throw new Error("unconsumed");
        if (typeof result !== "number" || !isFinite(result)) throw new Error("notfinite");
        var rounded = Math.round(result * 100) / 100;
        return { valid: true, display: String(rounded), value: rounded };
    } catch(e) {
        var msg = e.message || String(e);
        if (msg === "div0" || msg === "mod0") return { valid: false, display: "Division by zero", value: "" };
        if (msg === "unclosed") return { valid: false, display: "Unclosed parenthesis", value: "" };
        if (msg === "bad") return { valid: false, display: "Invalid expression", value: "" };
        if (msg === "unconsumed") return { valid: false, display: "Trailing operators", value: "" };
        if (msg === "notfinite") return { valid: false, display: "Invalid result", value: "" };
        return { valid: false, display: "?", value: "" };
    }
}

// ── Valid expressions ────────────────────────────────────────────────────────
(function testBasicArithmetic() {
    assert.strictEqual(evaluateCalc("2+2").valid, true);
    assert.strictEqual(evaluateCalc("2+2").value, 4);
    assert.strictEqual(evaluateCalc("10-3").valid, true);
    assert.strictEqual(evaluateCalc("10-3").value, 7);
    assert.strictEqual(evaluateCalc("3*4").valid, true);
    assert.strictEqual(evaluateCalc("3*4").value, 12);
    assert.strictEqual(evaluateCalc("15/3").valid, true);
    assert.strictEqual(evaluateCalc("15/3").value, 5);
    console.log("OK testBasicArithmetic");
})();

(function testOrderOfOperations() {
    assert.strictEqual(evaluateCalc("2+3*4").valid, true);
    assert.strictEqual(evaluateCalc("2+3*4").value, 14); // 2 + (3*4) = 14, not (2+3)*4 = 20
    assert.strictEqual(evaluateCalc("10-2*3").valid, true);
    assert.strictEqual(evaluateCalc("10-2*3").value, 4);
    assert.strictEqual(evaluateCalc("2*3+4").valid, true);
    assert.strictEqual(evaluateCalc("2*3+4").value, 10);
    console.log("OK testOrderOfOperations");
})();

(function testParentheses() {
    assert.strictEqual(evaluateCalc("(2+3)*4").valid, true);
    assert.strictEqual(evaluateCalc("(2+3)*4").value, 20);
    assert.strictEqual(evaluateCalc("2*(3+4)").valid, true);
    assert.strictEqual(evaluateCalc("2*(3+4)").value, 14);
    assert.strictEqual(evaluateCalc("(1+2)*(3+4)").valid, true);
    assert.strictEqual(evaluateCalc("(1+2)*(3+4)").value, 21);
    console.log("OK testParentheses");
})();

(function testUnaryMinus() {
    assert.strictEqual(evaluateCalc("-5").valid, true);
    assert.strictEqual(evaluateCalc("-5").value, -5);
    assert.strictEqual(evaluateCalc("--5").valid, true);
    assert.strictEqual(evaluateCalc("--5").value, 5);
    assert.strictEqual(evaluateCalc("2+-3").valid, true);
    assert.strictEqual(evaluateCalc("2+-3").value, -1);
    console.log("OK testUnaryMinus");
})();

(function testModulo() {
    assert.strictEqual(evaluateCalc("10%3").valid, true);
    assert.strictEqual(evaluateCalc("10%3").value, 1);
    assert.strictEqual(evaluateCalc("17%5").valid, true);
    assert.strictEqual(evaluateCalc("17%5").value, 2);
    console.log("OK testModulo");
})();

(function testDecimalResults() {
    assert.strictEqual(evaluateCalc("10/4").valid, true);
    assert.strictEqual(evaluateCalc("10/4").value, 2.5);
    assert.strictEqual(evaluateCalc("1/3").valid, true);
    assert.strictEqual(evaluateCalc("1/3").display, "0.33"); // rounded
    console.log("OK testDecimalResults");
})();

// ── Invalid expressions — must be rejected ─────────────────────────────────
(function testInvalidCharacters() {
    assert.strictEqual(evaluateCalc("2+2@").valid, false);
    assert.strictEqual(evaluateCalc("2$+2").valid, false);
    assert.strictEqual(evaluateCalc("2&2").valid, false);
    assert.strictEqual(evaluateCalc("abc").valid, false);
    assert.strictEqual(evaluateCalc("1+abc").valid, false);
    console.log("OK testInvalidCharacters");
})();

(function testMalformedNumbers() {
    assert.strictEqual(evaluateCalc("1.2.3+1").valid, false);
    assert.strictEqual(evaluateCalc("1.2.3+1").display, "Invalid number");
    console.log("OK testMalformedNumbers");
})();

(function testUnmatchedParentheses() {
    assert.strictEqual(evaluateCalc("(1+2").valid, false);
    assert.strictEqual(evaluateCalc("(1+2))").valid, false);
    assert.strictEqual(evaluateCalc("((1+2)").valid, false);
    assert.strictEqual(evaluateCalc("1+2)").valid, false);
    assert.strictEqual(evaluateCalc(")1+2(").valid, false);
    console.log("OK testUnmatchedParentheses");
})();

(function testTrailingOperators() {
    assert.strictEqual(evaluateCalc("2+").valid, false);
    assert.strictEqual(evaluateCalc("2*").valid, false);
    // Trailing operator with no operand throws "bad" which maps to "Invalid expression"
    assert.strictEqual(evaluateCalc("2+").display, "Invalid expression");
    console.log("OK testTrailingOperators");
})();

(function testDivideByZero() {
    assert.strictEqual(evaluateCalc("1/0").valid, false);
    assert.strictEqual(evaluateCalc("1/0").display, "Division by zero");
    assert.strictEqual(evaluateCalc("10%0").valid, false);
    assert.strictEqual(evaluateCalc("10%0").display, "Division by zero");
    console.log("OK testDivideByZero");
})();

(function testEmptyAndWhitespace() {
    assert.strictEqual(evaluateCalc("").valid, false);
    assert.strictEqual(evaluateCalc("   ").valid, false);
    assert.strictEqual(evaluateCalc("  ").display, "?");
    console.log("OK testEmptyAndWhitespace");
})();

(function testNonFiniteResults() {
    // Division of small number by very small number could overflow
    // But in JS, 1/0 = Infinity which we catch
    assert.strictEqual(evaluateCalc("1/0").valid, false);
    assert.strictEqual(evaluateCalc("0/0").valid, false);
    console.log("OK testNonFiniteResults");
})();

// ── Error display messages ───────────────────────────────────────────────────
(function testErrorMessages() {
    assert.strictEqual(evaluateCalc("abc").display, "Invalid character");
    assert.strictEqual(evaluateCalc("(1+2").display, "Unclosed parenthesis");
    assert.strictEqual(evaluateCalc("2+").display, "Invalid expression");
    assert.strictEqual(evaluateCalc("1/0").display, "Division by zero");
    console.log("OK testErrorMessages");
})();

// ── Invalid results are not copyable ──────────────────────────────────────
(function testInvalidResultsNotCopyable() {
    var r = evaluateCalc("(1+2");
    assert.strictEqual(r.valid, false);
    assert.strictEqual(r.value, ""); // empty string = not copyable
    console.log("OK testInvalidResultsNotCopyable");
})();

console.log("noxflow calculator validation fixtures passed");
