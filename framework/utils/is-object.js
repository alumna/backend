const is_object = function ( item, must_be_filled = false ) {

	let result = ( item && typeof item === 'object' && !Array.isArray( item ) )

	return ( result && must_be_filled ) ? Object.keys( item ).length : result;
}

module.exports = is_object;