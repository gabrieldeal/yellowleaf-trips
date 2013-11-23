function getRecommendedZoom(map, mapType, points) {
  var pointData = _getPointData(points);
  var bounds = new GLatLngBounds(pointData["sw"], pointData["ne"]);
  var zoomForPoints = map.getBoundsZoomLevel(bounds);

  var zoomForType = _getZoomForMapType(mapType);

  return _min(zoomForPoints, zoomForType);
}

function renderMap(points, options, mapType) {
  //  if (mapType == 'topo') {
  //    mapType = 'satellite';
  //  }

  if (! GBrowserIsCompatible()) {
    alert("Sorry, the Google Maps API is not compatible with this browser");
    return;
  }

  var pointData = _getPointData(points);

  var centerPoint = pointData["center"];

  _setMessage(centerPoint);

  var map = new GMap2(document.getElementById('map1'), options); 
  map.addControl(new GMapTypeControl());
  map.setCenter(centerPoint);

  GEvent.addListener(map, "click", function(marker, point) {
		       if (marker) {
			 return;
		       }
		       _setMessage(point);
		     });

  if (mapType == "satellite") {
    map.setMapType(G_SATELLITE_MAP);
  } else if(mapType == "topo") {
    var topoMapType = WMSCreateMap('Topo', 'USGS image from TerraServer-USA', 'http://www.terraserver-usa.com/ogcmap6.ashx', 'DRG', 'image/jpeg', false, 4, 17, [], 't');
    map.addMapType(topoMapType);
    map.setMapType(topoMapType);
  }
            
  for (var i = 0; i < points.length; ++i) {
    var point = new GLatLng(points[i]["lat"], points[i]["lon"]);
    var name = points[i]["name"];
    map.addOverlay(_createMarker(point, name));
  }

  return map;
}

//////////////////////////////////////////////////////////////////////

function _getZoomForMapType(mapType) {


  //  if (mapType == 'topo') {
  //    mapType = 'satellite';
  //  }


  var zoom = 8;
  if (mapType == 'topo') {
    zoom = 15;
  } else if (mapType == 'satellite') {
    zoom = 10;
  }

  return zoom;
}

function _setMessage(point) {
  if (document.getElementById("latlon")) {
    document.getElementById("latlon").innerHTML = point.x.toFixed(4) + " " + point.y.toFixed(4) + " NAD83";
  }
}

function _createMarker(point, name) {
  var marker = new GMarker(point);
  GEvent.addListener(marker, "click", function() {
		       marker.openInfoWindowHtml(name + " " + point.toString());
		     });
  return marker;
}

function _min(a, b) {
  return a < b ? a : b;
}
function _max(a, b) {
  return a > b ? a : b;
}
function _getPointData(points) {
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

  return { sw: new GLatLng(min_lat, min_lon),
      ne: new GLatLng(max_lat, max_lon),
      center: new GLatLng(min_lat + (max_lat - min_lat) / 2,
			  min_lon + (max_lon - min_lon) / 2),
      };
}
//////////////////////////////////////////////////////////////////////

function getParameter(name) {
  var url = window.location.href;
  var paramsStart = url.indexOf("?");

  if(paramsStart != -1){

    var paramString = url.substr(paramsStart + 1);
    var tokenStart = paramString.indexOf(name);

    if(tokenStart != -1){

      paramToEnd = paramString.substr(tokenStart + name.length + 1);
      var delimiterPos = paramToEnd.indexOf("&");

      if(delimiterPos == -1){
	return paramToEnd;
      }
      else {
	return paramToEnd.substr(0, delimiterPos);
      }
    }
  }
}
function getParameters() {

  var params = new Array();
  var url = window.location.href;
  var paramsStart = url.indexOf("?");
  var hasMoreParams = true;

  if(paramsStart != -1){

    var paramString = url.substr(paramsStart + 1);
    var params = paramString.split("&");
    for(var i = 0 ; i < params.length ; i++) {

      var pairArray = params[i].split("=");

      if(pairArray.length == 2){
	params[pairArray[0]] = pairArray[1];
      }

    }
    return params;
  }
  return null;
}

//////////////////////////////////////////////////////////////////////
// Web Map Service map types.
// Copyright © 2005,2006 by Jef Poskanzer <jef@mail.acme.com>.
// http://www.acme.com/javascript/
function WMSCreateMap( name, copyright, baseUrl, layer, format, transparent, minResolution, maxResolution, extraTileLayers, urlArg )
{
  var tileLayer = new GTileLayer( new GCopyrightCollection( copyright ), minResolution, maxResolution );
  tileLayer.baseUrl = baseUrl;
  tileLayer.layer = layer;
  tileLayer.format = format;
  tileLayer.transparent = transparent;
  tileLayer.getTileUrl = WMSGetTileUrl;
  tileLayer.getCopyright = function () { return { prefix: '', copyrightTexts: [ copyright ] }; };
  var tileLayers = [];
  for ( var i in extraTileLayers )
    tileLayers.push( extraTileLayers[i] );
  tileLayers.push( tileLayer );
  return new GMapType( tileLayers, G_SATELLITE_MAP.getProjection(), name, { errorMessage: _mMapError, urlArg: 'o' } );
}
function WMSGetTileUrl( tile, zoom )
{
  var southWestPixel = new GPoint( tile.x * 256, ( tile.y + 1 ) * 256 );
  var northEastPixel = new GPoint( ( tile.x + 1 ) * 256, tile.y * 256 );
  var southWestCoords = G_NORMAL_MAP.getProjection().fromPixelToLatLng( southWestPixel, zoom );
  var northEastCoords = G_NORMAL_MAP.getProjection().fromPixelToLatLng( northEastPixel, zoom );
  var bbox = southWestCoords.lng() + ',' + southWestCoords.lat() + ',' + northEastCoords.lng() + ',' + northEastCoords.lat();
  var transparency = this.transparent ? '&TRANSPARENT=TRUE' : '';
  return this.baseUrl + '?VERSION=1.1.1&REQUEST=GetMap&LAYERS=' + this.layer + '&STYLES=&SRS=EPSG:4326&BBOX=' + bbox + '&WIDTH=256&HEIGHT=256&FORMAT=' + this.format + '&BGCOLOR=0xCCCCCC&EXCEPTIONS=INIMAGE' + transparency;
}
//////////////////////////////////////////////////////////////////////
