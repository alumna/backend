// Utils
const is_object 									= require( './utils/is-object' );
const { prepare_context, prepare_args, run_chain }	= require( './utils/hook-utils' );

class Hook {

	constructor ( app, service, path, hook_holder = 'service' ) {

		this.hook_holder = hook_holder
		
		this.hooks = {
			before: [],
			after:  [],
			error:  []
		}

		// Prepare service hooks

		if ( hook_holder == 'service' )
			for( const type in this.hooks )
				this.hooks[ type ] = { all: [], find: [], get: [], create: [], update: [], patch: [], remove: [] };

	}

	async run ( read_only_context, args, method, event ) {

		/* PREPARE CONTEXT FOR BEFORE HOOKS */
		let context = prepare_context( read_only_context, args );

		/* RUN HOOKS */
		let result;

		try {

			/* APP AND SERVICE "BEFORE" HOOKS */
			context = await run_chain( context, read_only_context, this.hooks.before[ method ], 'before', method );

			/* SERVICE METHOD FUNCTION */
			context.result = await context.service.methods[ method ]( ...prepare_args( args ) );

			/* APP AND SERVICE "AFTER" HOOKS */
			context = await run_chain( context, read_only_context, this.hooks.after[ method ], 'after', method );

		} catch( error ) {
			
			context.error = error;

			/* APP AND SERVICE "ERROR" HOOKS */
			context = await run_chain( context, read_only_context, this.hooks.error[ method ], 'after', method );

			return context.error;

		}

		/* WHEN SUCCEED, EMIT THE EVENT */
		if ( event ) context.service.emit( event, context.result );

		return context.result;
	}

	add ( new_hooks ) {

		// If the new hooks are valid, merge them
		return ( is_object( new_hooks ) && this.walk( new_hooks ) ) ? this.walk( new_hooks, true ) : false;
	}

	// Walk to validade before apply
	walk ( new_hooks, validated = false ) {

		/* MOMENTS */
		for ( const type in new_hooks ) {

			/* VALIDATE MOMENTS */
			if ( !validated ) {
				
				// Inexistent hook type
				if ( !this.hooks[ type ] || ( this.hook_holder == 'app' && !this.valid( new_hooks[ type ] ) ) ) return false;

			}

			/* APPLY MOMENTS */
			else if ( this.hook_holder == 'app' ) this.merge( new_hooks[ type ], type );

			
			/* METHODS */
			if ( this.hook_holder == 'service' ) {

				for ( const method in new_hooks[ type ] ) {

					/* VALIDATE METHODS */
					if ( !validated ) {
						
						// Inexistent hook method
						if ( !this.hooks[ type ][ method ] || !this.valid( new_hooks[ type ][ method ] ) ) return false;
					}

					/* APPLY METHODS */
					else this.merge( new_hooks[ type ][ method ], type, method );

				}

			}

		}

		return true;

	}

	valid ( hooks ) {

		// A function is valid
		if ( typeof hooks == 'function' ) return true;

		// If not a function, an array of functions is also valid
		return ( Array.isArray( hooks ) && hooks.every( key => { return typeof hooks[ key ] == 'function' } ) );

	}

	// This merges a hook or array of hooks to existing ones
	merge ( new_hooks, type, method = false ) {

		const hooks = typeof new_hooks == 'function' ? [ new_hooks ] : new_hooks;

		// Hooks for a service method
		if ( method )
			this.hooks[ type ][ method ] = this.hooks[ type ][ method ].concat( hooks )
		
		// Or for an app
		else
			this.hooks[ type ] = this.hooks[ type ].concat( hooks )

		return true;

	}

}

module.exports = Hook;