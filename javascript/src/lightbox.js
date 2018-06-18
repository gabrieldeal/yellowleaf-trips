import Blueimp from 'blueimp-gallery';
import 'blueimp-gallery/css/blueimp-gallery.min.css';
import './lightbox.css';

export function initialize() {
  var imageLinks = document.getElementsByClassName('lightbox-image');
  for (var i = 0; i < imageLinks.length; i++) {
    var imageLink = imageLinks[i];

    imageLink.onclick = function (event) {
      event = event || window.event;

      var target = event.target || event.srcElement;
      var link = target.src ? target.parentNode : target;
      var options = {
        continuous: false,
        index: link,
        event: event,
      };
      Blueimp(imageLinks, options);
    };
  };
}
