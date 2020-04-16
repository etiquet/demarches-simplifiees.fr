import React, { useState, useEffect } from 'react';
import axios from 'axios';
import {
  Combobox,
  ComboboxInput,
  ComboboxPopover,
  ComboboxList,
  ComboboxOption
} from '@reach/combobox';
import '@reach/combobox/styles.css';
import PropTypes from 'prop-types';

let cache = {};
const useCitySearch = searchTerm => {
  const [addresses, setAddresses] = useState([]);
  useEffect(() => {
    if (searchTerm.trim() !== '') {
      let isFresh = true;
      fetchAddresses(searchTerm).then(addresses => {
        if (isFresh) setAddresses(addresses);
      });
      return () => (isFresh = false);
    }
  }, [searchTerm]);
  return addresses;
};

const fetchAddresses = value => {
  if (cache[value]) {
    return Promise.resolve(cache[value]);
  }
  return axios
    .get(`https://api-adresse.data.gouv.fr/search/?q=${value}&limit=5`)
    .then(result => {
      cache[value] = result;
      return result;
    });
};

const SearchInput = ({ getCoords }) => {
  const [searchTerm, setSearchTerm] = useState('');
  const addresses = useCitySearch(searchTerm);
  const handleSearchTermChange = event => {
    setSearchTerm(event.target.value);
  };

  return (
    <Combobox aria-label="addresses">
      <ComboboxInput
        placeholder="Saisissez au moins 2 caractères"
        className="city-search-input"
        style={{
          font: 'inherit',
          padding: '.25rem .5rem',
          width: '100%',
          minHeight: '62px'
        }}
        onChange={handleSearchTermChange}
      />
      {addresses.data && (
        <ComboboxPopover
          style={{
            borderTopColor: '#ddd',
            marginTop: '-1px',
            boxShadow: '0 2px 4px rgba(0,0,0,.15)',
            position: 'absolute',
            width: '400px',
            left: '351px',
            top: '5562px'
          }}
          className="shadow-popup"
        >
          {addresses.data.features.length > 0 ? (
            <ComboboxList>
              {addresses.data.features.map(feature => {
                const str = `${feature.properties.name}, ${feature.properties.city}`;
                return (
                  <ComboboxOption
                    onClick={() => getCoords(feature.geometry.coordinates)}
                    key={str}
                    value={str}
                  />
                );
              })}
            </ComboboxList>
          ) : (
            <span style={{ display: 'block', margin: 8 }}>Aucun résultat</span>
          )}
        </ComboboxPopover>
      )}
    </Combobox>
  );
};

SearchInput.propTypes = {
  getCoords: PropTypes.func
};

export default SearchInput;
