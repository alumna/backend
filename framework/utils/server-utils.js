const methods = {

	find ( service ) {
		
		return {
			verb: 'get',
			sufix: '',
			async execute ( params ) {
				return await service.find( params )
			}
		}

	},

	get ( service ) {
		
		return {
			verb: 'get',
			sufix: '/:id',
			async execute ( params, req ) {
				return await service.get( req.params.id, params )
			}
		}

	},

	create ( service ) {
		
		return {
			verb: 'post',
			sufix: '',
			async execute ( params, req ) {
				return await service.create( req.body, params )
			}
		}

	},

	update ( service ) {
		
		return {
			verb: 'put',
			sufix: '/:id',
			async execute ( params, req ) {
				return await service.update( req.params.id, req.body, params )
			}
		}

	},

	patch ( service ) {
		
		return {
			verb: 'patch',
			sufix: '/:id',
			async execute ( params, req ) {
				return await service.patch( req.params.id, req.body, params )
			}
		}

	},

	remove ( service ) {
		
		return {
			verb: 'delete',
			sufix: '/:id',
			async execute ( params, req ) {
				return await service.remove( req.params.id, params )
			}
		}

	}

}

module.exports = { methods }

