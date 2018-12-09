"use strict";

export default function resizeThumbnail(img, size) {
    if (img.width > img.height) {
	img.width = size;
	img.removeAttribute("height");
    } else {
	img.height = size;
        img.removeAttribute("width");
    }
}
