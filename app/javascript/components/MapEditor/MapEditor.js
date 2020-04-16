import React, { useState, useRef } from 'react';
import PropTypes from 'prop-types';
import ReactMapboxGl from 'react-mapbox-gl';
import { ZoomControl } from 'react-mapbox-gl';
import DrawControl from 'react-mapbox-gl-draw';
import SwitchMapStyle from './SwitchMapStyle';
import SearchInput from './SearchInput';
import '@mapbox/mapbox-gl-draw/dist/mapbox-gl-draw.css';

const Map = ReactMapboxGl({});

const MapEditor = ({ featureCollection: { bbox, features, type } }) => {
  const drawControl = useRef(null);
  const [style, setStyle] = useState('ortho');
  const [coords, setCoords] = useState([1.7, 46.9]);
  const [zoom, setZoom] = useState([5]);

  const mapStyle =
    style === 'ortho'
      ? 'https://raw.githubusercontent.com/etalab/cadastre.data.gouv.fr/master/components/react-map-gl/styles/ortho.json'
      : 'https://raw.githubusercontent.com/etalab/cadastre.data.gouv.fr/master/components/react-map-gl/styles/vector.json';

  let selections = [];
  const onDrawCreate = ({ features }) => {
    const updateArray = [...selections, ...features];
    selections = [...updateArray];
  };

  const onDrawUpdate = ({ features }) => {
    let updatedArray = selections.filter(
      selection => selection.id !== features[0].id
    );
    selections = [...updatedArray, ...features];
  };

  const onDrawDelete = ({ features }) => {
    let updatedArray = selections.filter(
      selection => selection.id !== features[0].id
    );
    selections = [...updatedArray];
  };

  const onMapLoad = () => {
    if (features.selectionsUtilisateur) {
      features.selectionsUtilisateur.map(selection => {
        drawControl.current.draw.add({
          type: 'Feature',
          properties: {},
          geometry: selection.geometry
        });
      });
    }
  };

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
        //onStyleLoad={() => onMapLoad()}
        fitBounds={bbox}
        fitBoundsOptions={{ padding: 100 }}
        center={coords}
        zoom={zoom}
        style={mapStyle}
        containerStyle={{
          height: '500px'
        }}
      >
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
    features: PropTypes.array
  })
};

export default MapEditor;
