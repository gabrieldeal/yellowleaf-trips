var map = new GMap2(document.getElementById("map"));
geocoder = new GClientGeocoder();
var WMS_TOPO_MAP;
var gInput = {};

function _createMarker(point, name) {
  var marker = new GMarker(point);
  if (name) {
    GEvent.addListener(marker, "click", function() {
			 marker.openInfoWindowHtml(name);
		       });
  }
  return marker;
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
function _min(a, b) {
  return a < b ? a : b;
}
function _max(a, b) {
  return a > b ? a : b;
}

function ShowMeTheMap()
{
  var lat = gup('lat');
  var lon = gup('lon');
  var type = gup('type');
  var requestedZoom = gup('zoom') ? parseInt(gup('zoom')) : 2;
  requestedZoom = 17 - requestedZoom; // convert from v1 to v2 zoom
  var points = gup('points') ? gup('points') : [ ];

  if (! GBrowserIsCompatible()) {
    alert("Sorry, the Google Maps API is not compatible with this browser");
    return;
  }
    
  // create the map
  map.addControl(new GLargeMapControl());
  map.addControl(new GMapTypeControl());
  map.addControl(new GScaleControl());

  // Web Map Service map types.
  // Copyright ? 2005,2006 by Jef Poskanzer <jef@mail.acme.com>.
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
    return new GMapType( tileLayers, G_SATELLITE_MAP.getProjection(), name, { errorMessage: "Data not Available", urlArg: 'o' } );
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


  WMS_TOPO_MAP = WMSCreateMap( 'USGS Topo', 'Imagery by USGS / Web Service by TerraServer', 'http://www.terraserver-usa.com/ogcmap6.ashx', 'DRG', 'image/jpeg', false, 4, 17, [], 't' );

  map.addMapType(WMS_TOPO_MAP);
  map.addMapType(G_PHYSICAL_MAP);

  var center;
  var zoom;
  if (points.length == 0) {
    center = new GLatLng(lat, lon);
    zoom = requestedZoom;
  } else {
    var pointData = _getPointData(points);
    center = pointData["center"];
    var bounds = new GLatLngBounds(pointData["sw"], pointData["ne"]);
    var zoomForPoints = map.getBoundsZoomLevel(bounds);
    zoom = _min(zoomForPoints, requestedZoom);
  }

  // V1 API
  // map.centerAndZoom(new GLatLng(lat, lon), zoom);
    map.setCenter(center, zoom);

  if (type == 'usgs') {
    map.setMapType(WMS_TOPO_MAP);
  } else {
    map.setMapType(G_PHYSICAL_MAP);                    
  }
                    
  GEvent.addListener(map, "moveend", function() {
		       updateDocument(map);
		     });

  for (var i = 0; i < points.length; ++i) {
    var point = new GLatLng(points[i]["lat"], points[i]["lon"]);
    var name = points[i]["name"];
    var marker =_createMarker(point, name);
    map.addOverlay(marker);
  }


  updateDocument(map);
}

function setInput(name, value) {
  gInput[name] = value;
}

// http://www.netlobo.com/url_query_string_javascript.html
function gup( name )
{
  name = name.replace(/[\[]/,"\\\[").replace(/[\]]/,"\\\]");
  if (gInput[name]) {
    return gInput[name];
  }

  var regexS = "[\\?&]"+name+"=([^&#]*)";
  var regex = new RegExp( regexS );
  var results = regex.exec( window.location.href );
  if( results == null )
    return "";
  else
    return results[1];
}

function updateDocument(map)
{
  var center = map.getCenter();

  // V1 API
  //  var zoom = map.getZoomLevel();
  var zoom = map.getZoom();

  var latElem = document.getElementById("lat");
  if (latElem) {
    latElem.innerHTML = center.lat();
  }

  var lonElem = document.getElementById("lon");
  if (lonElem) {
    lonElem.innerHTML = center.lng();
  }

  var type = 'terrain';
  if (map.getCurrentMapType().getName() == WMS_TOPO_MAP.getName()) {
    type = 'usgs';
  }

  var urlElement = document.getElementById("url");
  if (urlElement) {
    urlElement.innerHTML = location.protocol + location.host + location.pathname + '?lon=' + center.lng() + '&lat=' + center.lat() + '&zoom=' + zoom + '&type=' + type;
  }
}

//This function handles the geocoding
function showAddress(address) {
  if (geocoder) {
    geocoder.getLatLng(
		       address,
		       function(point) {
			 if (!point) {
			   alert(address + " not found");
			 } else {
			   map.setCenter(point, 11);
			 }
		       }
		       );
  }
}

