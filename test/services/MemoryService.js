class MemoryService {
	
	constructor() {
		this.memory = {}
		this.id = 0
	}

	async find () {
		return this.memory
	}

	async get( id, params ) {

		const record = this.memory[ id ]

		if ( record )
			return record;

		const error = new Error( 'Not Found' );
		error.name  = 'NotFound'
		error.code  = 404

		throw error;
	}

	async create ( data ) {
		
		const record = data
		record._id = ++this.id
		this.memory[ this.id ] = record;
		return record;
	}

	async update( id, data ) {

		if ( this.memory[ id ] )
			return this.memory[ id ] = data;

		const error = new Error( 'Not Found' );
		error.name  = 'NotFound'
		error.code  = 404

		throw error;
	}
	
	async patch( id, data ) {

		if ( this.memory[ id ] )
			return this.memory[ id ] = Object.assign( this.memory[ id ], data );

		const error = new Error( 'Not Found' );
		error.name  = 'NotFound'
		error.code  = 404

		throw error;
	}
	
	async remove( id ) {

		const record = this.memory[ id ]

		if ( record && delete this.memory[ id ] )
			return record;

		const error = new Error( 'Not Found' );
		error.name  = 'NotFound'
		error.code  = 404

		throw error;
	}

	async setup ( app, path ) {

		this.setup_done = 'done'

	}
}

export default MemoryService;