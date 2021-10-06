const hashPassword = function ( context ) {

	context.data.password = 'hashedPasswordTest123'

	return context;

}

export { hashPassword };