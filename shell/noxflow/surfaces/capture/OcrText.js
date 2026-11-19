.pragma library

function validLanguage(value) {
    var language = String(value || "").trim();
    return /^[A-Za-z][A-Za-z0-9_+.-]{0,63}$/.test(language) ? language : "";
}

function normalize(text, rawMode, singleLine) {
    var source = String(text || "").replace(/\r\n?/g, "\n");
    if (rawMode) {
        return source.split("\n").map(function(line) {
            return line.replace(/[\t ]+$/g, "");
        }).join("\n").trim();
    }

    var paragraphs = source.split(/\n[\t ]*\n+/).map(function(paragraph) {
        return paragraph.replace(/\s+/g, " ").trim();
    }).filter(function(paragraph) { return paragraph !== ""; });
    return paragraphs.join(singleLine ? " " : "\n\n").trim();
}

