const hidePassword = function ( context ) {

	delete context.result.password

	return context;

}

const hideAllPasswords = function ( context ) {

	const users = context.result

	for ( let id in users )
		delete context.result[ id ].password

	return context;

}

export { hidePassword, hideAllPasswords };