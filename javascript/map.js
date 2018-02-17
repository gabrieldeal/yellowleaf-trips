var gInput = {};
function setInput(name, value) {
    gInput[name] = value;
}

// http://www.netlobo.com/url_query_string_javascript.html
function gup(name) {
    if (gInput[name]) {
	return gInput[name];
    }

    name = name.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]");

    var regexS = "[\\?&]"+name+"=([^&#]*)";
    var regex = new RegExp(regexS);
    var results = regex.exec(window.location.href);
    if (results === null) {
	return "";
    } else {
	return results[1];
    }
}

function getPointsSummary(points) {
  var first = points[0];
  var min_lat = first["lat"];
  var min_lon = first["lon"];
  var max_lat = first["lat"];
  var max_lon = first["lon"];

  for (var i = 0; i < points.length; ++i) {
    var lat = points[i]["lat"];
    var lon = points[i]["lon"];
    min_lat = _min(min_lat, lat);
    min_lon = _min(min_lon, lon);
    max_lat = _max(max_lat, lat);
    max_lon = _max(max_lon, lon);
  }

  return {
      sw: new google.maps.LatLng(min_lat, min_lon),
      ne: new google.maps.LatLng(max_lat, max_lon),
      center: new google.maps.LatLng(min_lat + (max_lat - min_lat) / 2,
				     min_lon + (max_lon - min_lon) / 2),
  };
}
function _min(a, b) {
    return a < b ? a : b;
}
function _max(a, b) {
    return a > b ? a : b;
}

function getPoints() {
    var points = gup('points');
    if (! points) {
	points = [];
    } else if (typeof points === "string") {
	points = decodeURIComponent(points);
	points = JSON.parse(points);
    }

    return points;
}

function initialize() {
    var defaultZoom = 11;

    var mapOptions = {
	zoom: defaultZoom,
	mapTypeId: google.maps.MapTypeId.TERRAIN
    };

    var points = getPoints();
    var pointsSummary;
    if (points.length > 0) {
	pointsSummary = getPointsSummary(points);
	mapOptions.center = pointsSummary.center; // will be ignored if we have a KML
    }

    var map = new google.maps.Map(document.getElementById('map'), mapOptions);

    var kmlUrl = gup('kmlUrl');
    if (kmlUrl) {
	var kmlLayer = new google.maps.KmlLayer({ url: kmlUrl });
        kmlLayer.setMap(map);
    }

    if (points.length > 1) {
	var bounds = new google.maps.LatLngBounds(pointsSummary.sw, pointsSummary.ne);
	map.fitBounds(bounds);

	google.maps.event.addListenerOnce(map, 'bounds_changed', function(event) {
            if (this.getZoom() > defaultZoom){
		this.setZoom(defaultZoom);
            }
	});
    }

    for (var i = 0; i < points.length; ++i) {
    	var point = points[i];
    	var marker = new google.maps.Marker({
    	    position: new google.maps.LatLng(point.lat, point.lon),
    	    clickable: true,
    	    title: point.name,
    	    map: map
    	});
    }
}

google.maps.event.addDomListener(window, 'load', initialize);
