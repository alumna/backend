const is_object = function ( item ) {

	return item && typeof item === 'object' && !Array.isArray( item );
}

export default is_object;