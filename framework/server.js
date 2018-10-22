// Performant express-like framework
const polka 		= require( 'polka' );
const send 			= require( '@polka/send-type' );

// Server utils
const { methods } 	= require( './utils/server-utils' );

// HTTP middlewares
const cors 			= require( 'cors' );
const bodyParser 	= require( 'body-parser' );

// Integration with http server and sockets with services 
class Server {

	constructor () {

		this.polka = polka();

		this.polka.use( cors() );

		this.polka.use( bodyParser.json() );

		this.polka.use( bodyParser.urlencoded( { extended: true } ) );

	}

	async mount ( method, service_path, service ) {

		// If a method isn't implemented by the developer,
		// just skip it.
		if ( typeof service.methods[ method ] != 'function' ) return;

		// Otherwise, mount it
		const selected = methods[ method ]( service );

		// Otherwise, create the "params" object and mount the
		// service method to its correspondent http API endpoint/url
		const params = {
			provider: 'rest'
		}

		// Here is where the "magic happens"
		// Each mounted method will have its own and correct URL and HTTP verb.
		// Nice!
		this.polka[ selected.verb ]( '/' + service_path + selected.sufix, async ( req, res ) => {

			params.query = req.query;

			try	{
				return send( res, 200, await selected.execute( params, req ));
			}

			catch ( error ) {
				
				const standard = {
					name: 'BadRequest',
					message: '',
					code: 400
				}

				error = Object.assign( error, standard );

				return send( res, error.code, { error: { name: error.name, message: error.message, code: error.code } } );
			}

		});

	}

	async add ( service_path, service ) {

		// For each existent method on the original service (provided by the developer)
		// we create the correspondent http API endpoint, automatically

		const promises = []

		for ( const method in methods )
			promises.push( this.mount( method, service_path, service ) )


		return await Promise.all( promises );
	}

	start ( port, hostname ) {

		return this.polka.listen( port, hostname )

	}

}

// ---

module.exports = Server;