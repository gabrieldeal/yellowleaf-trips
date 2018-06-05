import Lightbox from 'lightbox2';
import jquery from 'jquery';
import 'lightbox2/dist/css/lightbox.min.css';

export function initialize() {
  Lightbox.option({
    disableScrolling: true,
    fadeDuration: 250,
    imageFadeDuration: 250,
    positionFromTop: 10,
    resizeDuration: 250,
  });
}
