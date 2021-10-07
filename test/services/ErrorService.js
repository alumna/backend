class ErrorService {
	
	constructor() {
		this.data = []
	}

	async find () {
		
        throw new Error( 'Test message' )

	}
}

export default ErrorService;