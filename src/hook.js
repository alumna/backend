// Utils
import is_object 									from './utils/is-object';
import { prepare_context, prepare_args, run_chain }	from './utils/hook-utils';

const methods = () => { return { all: [], find: [], get: [], create: [], update: [], patch: [], remove: [] } };

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
			for( const moment in this.hooks )
				this.hooks[ moment ] = methods();

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

		if ( !this.valid( new_hooks ) )
			return false;

		this.walk( new_hooks );
	}

	valid ( new_hooks ) {

		if ( !is_object( new_hooks ) )
			return false;

		for ( const moment in this.hooks ) {

			const hook = new_hooks[ moment ]

			if ( !hook )
				continue;

			if ( typeof hook == 'function' && this.hook_holder == 'app' )
				continue;

			if ( !is_object( hook ) || !this.valid_action( hook ) )
				return false;
		}

		return true;

	}

	valid_action ( hook ) {

		const actions = methods()

		for ( const action in actions ) {

			const hook_action = hook[ action ]

			if ( !hook_action )
				continue;

			if ( !Array.isArray( hook_action ) || !hook_action.every( element => typeof element == 'function') )
				return false;

		}

		return true;

	}

	// Walk to validade before apply
	walk ( new_hooks ) {

		

		const actions = methods()

		/* MOMENTS */
		for ( const moment in new_hooks ) {

			if ( this.hook_holder == 'app' )
				return this.merge( new_hooks[ moment ], moment );

			for ( const action in actions )
				if ( new_hooks[ moment ][ action ] )
					this.merge( new_hooks[ moment ][ action ], moment, action );
		}

		return true;

	}

	// This merges a hook or array of hooks to existing ones
	merge ( new_hooks, moment, method = false ) {

		const hooks = typeof new_hooks == 'function' ? [ new_hooks ] : new_hooks;

		// Hooks for a service method
		if ( method )
			this.hooks[ moment ][ method ] = this.hooks[ moment ][ method ].concat( hooks )
		
		// Or for an app
		else
			this.hooks[ moment ] = this.hooks[ moment ].concat( hooks )

		return true;

	}

}

export default Hook;