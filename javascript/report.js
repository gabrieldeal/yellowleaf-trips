"use strict";

function resizeThumbnail(img, size) {
    if (img.clientWidth > img.clientHeight) {
	img.width = size;
	img.removeAttribute("height");
    } else {
	img.height = size;
	img.foo = "bar";
	img.removeAttribute("width");
    }
}
