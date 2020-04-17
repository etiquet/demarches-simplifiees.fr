import React, { useState, useRef, useEffect } from 'react';
import PropTypes from 'prop-types';
import ReactMapboxGl, { GeoJSONLayer } from 'react-mapbox-gl';
import { ZoomControl } from 'react-mapbox-gl';
import DrawControl from 'react-mapbox-gl-draw';
import SwitchMapStyle from './SwitchMapStyle';
import SearchInput from './SearchInput';
import { fire, delegate } from '@utils';
import '@mapbox/mapbox-gl-draw/dist/mapbox-gl-draw.css';

const Map = ReactMapboxGl({});

const MapEditor = ({ featureCollection: { bbox, features, id } }) => {
  const drawControl = useRef(null);
  const [style, setStyle] = useState('ortho');
  const [test, setTest] = useState([]);
  const [coords, setCoords] = useState([1.7, 46.9]);
  const [zoom, setZoom] = useState([5]);

  const selectionsUtilisateurs = features.filter(
    feature => feature.properties.source === 'selection_utilisateur'
  );
  console.log('render');
  const cadastresFeatureCollection = {
    type: 'FeatureCollection',
    features: []
  };

  for (let feature of features) {
    switch (feature.properties.source) {
      case 'cadastre':
        cadastresFeatureCollection.features.push(feature);
        break;
    }
  }

  const polygonCadastresFill = {
    'fill-color': '#EC3323',
    'fill-opacity': 0.3
  };

  const polygonCadastresLine = {
    'line-color': 'rgba(255, 0, 0, 1)',
    'line-width': 4,
    'line-dasharray': [1, 1]
  };

  const mapStyle =
    style === 'ortho'
      ? 'https://raw.githubusercontent.com/etalab/cadastre.data.gouv.fr/master/components/react-map-gl/styles/ortho.json'
      : 'https://raw.githubusercontent.com/etalab/cadastre.data.gouv.fr/master/components/react-map-gl/styles/vector.json';

  let selections = [];

  const createFeatureCollection = latLngs => {
    return {
      type: 'FeatureCollection',
      features: latLngs.map(featurePolygonLatLngs)
    };
  };

  const featurePolygonLatLngs = latLngs => {
    return {
      type: 'Feature',
      properties: {
        source: 'selection_utilisateur'
      },
      geometry: {
        type: 'Polygon',
        coordinates: [latLngs]
      }
    };
  };

  const onDrawCreate = ({ features }) => {
    const featureCollection = createFeatureCollection(
      features[0].geometry.coordinates
    );
    console.log(featureCollection);
    console.log(JSON.stringify(featureCollection));
  };

  const onDrawUpdate = ({ features }) => {
    const featureCollection = createFeatureCollection(
      features[0].geometry.coordinates
    );
    let input = document.querySelector(
      `input[data-feature-collection-id="${id}"]`
    );
    input.value = JSON.stringify(featureCollection);
    fire(input, 'change');
  };

  const onDrawDelete = ({ features }) => {
    console.log(features);
  };

  const onMapLoad = () => {
    if (selectionsUtilisateurs.length > 0) {
      selectionsUtilisateurs.map(selection => {
        drawControl.current.draw.add({
          type: 'Feature',
          properties: { source: 'selection_utilisateur' },
          geometry: selection.geometry
        });
      });
    }
  };

  useEffect(() => {
    setTest(features);
  }, [features]);

  return (
    <>
      <div
        style={{
          marginBottom: '62px'
        }}
      >
        <SearchInput
          getCoords={searchTerm => {
            setCoords(searchTerm);
            setZoom([17]);
          }}
        />
      </div>
      <Map
        onStyleLoad={() => onMapLoad()}
        fitBounds={bbox}
        fitBoundsOptions={{ padding: 100 }}
        center={coords}
        zoom={zoom}
        style={mapStyle}
        containerStyle={{
          height: '500px'
        }}
      >
        <GeoJSONLayer
          data={cadastresFeatureCollection}
          fillPaint={polygonCadastresFill}
          linePaint={polygonCadastresLine}
        />
        <DrawControl
          ref={drawControl}
          onDrawCreate={onDrawCreate}
          onDrawUpdate={onDrawUpdate}
          onDrawDelete={onDrawDelete}
          displayControlsDefault={false}
          controls={{
            point: true,
            line_string: true,
            polygon: true,
            trash: true
          }}
        />
        <div
          className="style-switch"
          style={{
            position: 'absolute',
            bottom: 0,
            left: 0
          }}
          onClick={() =>
            style === 'ortho' ? setStyle('vector') : setStyle('ortho')
          }
        >
          <SwitchMapStyle isVector={style === 'vector' ? true : false} />
        </div>

        <ZoomControl />
      </Map>
    </>
  );
};

MapEditor.propTypes = {
  featureCollection: PropTypes.shape({
    type: PropTypes.string,
    bbox: PropTypes.array,
    features: PropTypes.array,
    id: PropTypes.number
  })
};

export default MapEditor;
