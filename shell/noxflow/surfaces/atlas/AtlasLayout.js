.pragma library

function computeGrid(count, gridWidth, gridHeight, minCardWidth, minCardHeight, maxColumns) {
    var n = Math.max(0, Math.floor(Number(count) || 0));
    var width = Math.max(1, Number(gridWidth) || 1);
    var height = Math.max(1, Number(gridHeight) || 1);
    var minW = Math.max(1, Number(minCardWidth) || 360);
    var minH = Math.max(1, Number(minCardHeight) || 260);
    var maxCols = Math.max(1, Math.floor(Number(maxColumns) || 4));
    var fitCols = Math.max(1, Math.min(maxCols, Math.floor(width / minW)));

    var columns = 1;
    if (n <= 1 || width < minW * 2) {
        columns = 1;
    } else if (n <= 3) {
        columns = Math.min(n, fitCols);
    } else if (n === 4) {
        columns = Math.min(2, fitCols);
    } else if (n <= 6) {
        columns = Math.min(3, fitCols);
    } else {
        var ratio = Math.max(1, width / height);
        columns = Math.max(2, Math.min(
            fitCols,
            Math.ceil(n / 2),
            Math.ceil(Math.sqrt(n * ratio))
        ));
    }

    var rows = Math.max(1, Math.ceil(n / columns));
    var cellWidth = Math.floor(width / columns);
    var rawRowHeight = Math.floor(height / rows);
    var cellHeight = Math.max(minH, rawRowHeight);
    var scrolls = (rows * cellHeight) > height;

    return {
        columns: columns,
        rows: rows,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        scrolls: scrolls
    };
}
