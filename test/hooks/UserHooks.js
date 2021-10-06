import { hidePassword, hideAllPasswords } from './UserHooks/hidePassword.js'
import { hashPassword } from './UserHooks/hashPassword.js'

const addField = function ( context ) {

	context.data.newField = 'New field'
	return context;
}

export default {
	before: {
		all: [],
		find: [],
		get: [],
		create: [ addField, hashPassword ],
		update: [],
		patch: [],
		remove: []
	},

	after: {
		all: [],
		find: [ hideAllPasswords ],
		get: [ hidePassword ],
		create: [ hidePassword ],
		update: [ hidePassword ],
		patch: [ hidePassword ],
		remove: [ hidePassword ]
	},

	error: {
		all: [],
		find: [],
		get: [],
		create: [],
		update: [],
		patch: [],
		remove: []
	}
};