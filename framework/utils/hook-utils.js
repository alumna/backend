const prepare_context = function ( read_only_context, args ) {

	let context = redefine_context( read_only_context, {}, 'before' );

	/* PARAMS */
	context.params = Object.assign( { query: undefined, provider: undefined }, args.params );

	if ( args.id ) context.id = args.id;

	if ( args.data ) context.data = args.data;

	return context;

}

const prepare_args = function ( args ) {

	let service_args = []

	if ( args.id )     service_args.push( args.id );

	if ( args.data ) service_args.push( args.data );

	if ( args.params ) service_args.push( args.params );

	return service_args;

}

// Redefine read-only context' properties
const redefine_context = function ( read_only_context, modified = {}, type ) {

	modified.type = type;
	return Object.assign( modified, read_only_context )

}

const run_chain = async function ( context, read_only_context, functions, moment, method  ) {

	// When we are running hooks before a service method, first we need to run the app's before hooks
	if ( method && moment == 'before' )
		context = await run_chain( context, read_only_context, context.app.hook_chain.hooks[ moment ], moment );

	// ----------------------

	let length = functions.length;

	for ( let i = 0; i < length; i++ ) {

		// Using Promise.resolve at the function execution allows
		// to handle both asynchronous and synchronous functions
		context = await Promise.resolve( functions[ i ]( context ) );

		context = redefine_context( read_only_context, context, moment );

	}

	// ----------------------

	// When we are running hooks after a service method, we need to run the app's after hooks as well
	// Or, in the error's case, run the error hooks as well
	if ( method && ( moment == 'after' || moment == 'error' ) )
		context = await run_chain( context, read_only_context, context.app.hook_chain.hooks[ moment ], moment );

	return context;

}

module.exports = { prepare_context, prepare_args, run_chain }