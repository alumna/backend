// Node modules
import EventEmitter 	from 'events';
// Alumna modules
import Hook 			from './hook';


class Service extends EventEmitter {

	constructor( app, service, path ) {

		super();

		this.app        = app;
		this.methods    = service;
		this.path       = path;
		this.hook_chain = new Hook( app, this, path );

	}

	async find ( params ) {

		return await this.run( { params }, 'find' );

	}

	async get ( id, params ) {

		return await this.run( { id, params }, 'get' );

	}

	async create ( data, params ) {

		return await this.run( { data, params }, 'create', 'created' );

	}

	async update ( id, data, params ) {

		return await this.run( { id, data, params }, 'update', 'updated' );

	}

	async patch ( id, data, params ) {

		return await this.run( { id, data, params }, 'patch', 'patched' );

	}

	async remove ( id, params ) {

		return await this.run( { id, params }, 'remove', 'removed' );

	}

	async setup () {

		if ( this.methods.setup )
			return await Promise.resolve( this.methods.setup( this.app, this.path ) );
		else
			return true;
	}

	async run ( args, method, event ) {

		/* HOOKS CONTEXT */
		let context = {
			app: 		this.app,
			service: 	this,
			path: 		this.path,
			method
		}

		return await this.hook_chain.run( context, args, method, event );

	}

	hooks ( hook ) {

		return this.hook_chain.add( hook );

	}

}



export default Service;