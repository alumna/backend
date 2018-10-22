// Node modules
const EventEmitter 	= require( 'events' );

// Altiva modules
const Service 		= require( './service' );
const Hook 			= require( './hook' );

// Servers
const Server 		= require( './server' );

class Altiva extends EventEmitter {

	constructor () {

		super();

		this.services   = {};
		this.hook_chain = new Hook ( this, undefined, undefined, 'app' );
		this.server 	= new Server();

		// Pending promises returned from "use" method
		this.pending	= [];

		this.listening 	= false;

	}

	use ( service_path, service_logic ) {

		// Remove '/' from the beginning and end of service path
		if ( service_path.startsWith( '/' ) ) service_path = service_path.substring( 1 );
		if ( service_path.endsWith( '/' ) ) service_path = service_path.splice( 0, -1 );

		this.services[ service_path ] = new Service( this, service_logic, service_path );

		// Promise returned from "this.serverd.add(...)"
		const promise = this.server.add( service_path, this.services[ service_path ] );

		// If server is already running, setup the service
		// Otherwise, add the pending promise returned
		this.listening ? this.services[ service_path ].setup() : this.pending.push( promise );

	}

	service ( service_path ) {

		return this.services[ service_path ] ? this.services[ service_path ] : null;

	}

	hooks ( hook ) {

		return this.hook_chain.add( hook );

	}

	async setup () {

		// Ensure all server endpoints are mounted
		await Promise.all( this.pending );

		// Clear pending array
		this.pending = [];

		// Run the "setup" function on services that implement it
		const promises = [];

		for ( const service in this.services )
			promises.push( this.services[ service ].setup() );

		// Ensure all services are ready
		return await Promise.all( promises )

	}

	async listen ( port = 3000, hostname = undefined ) {

		await this.setup();
		await this.server.start( port, hostname );

		this.listening = true;

		console.log( '[Altiva Backend] Listening on ' + ( hostname ? hostname + ':' : 'port: ' ) + port );

	}

}

module.exports = new Altiva();