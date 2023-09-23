import Alumna 							from '../src/alumna.js';
import http 							from 'http';
import { get, patch, post, put, del } 	from 'httpie';

/* Services */
import MemoryService					from './services/MemoryService.js'
import IncompleteService				from './services/IncompleteService.js'
import ErrorService						from './services/ErrorService.js'


/* Hooks */
import UserHooks						from './hooks/UserHooks'

const backend = new Alumna();
backend.use( 'messages',   new MemoryService() )
backend.use( 'incomplete', new IncompleteService() )
backend.use( 'users',      new MemoryService() )
backend.use( 'errors',      new ErrorService() )


backend.service( 'users' ).hooks( UserHooks )


describe('Alumna Backend Tests', () => {

	beforeAll( async () => {
		
		await backend.listen()
		return;
	});

	describe('Messages API - Complete service class - No hooks', () => {

		test('0. Setup', done => {

			// expect( backend.service( 'messages' ).setupDone ).toBe( 'done' )
			done()
			
		});

		test('1. 404 on root URI', done => {

			http.get( 'http://127.0.0.1:3000/', response => {

				expect( response.statusCode ).toBe( 404 )
				done()

			})
			
		});

		test('2. Void messages collection', async () => {

			const response = await get( 'http://127.0.0.1:3000/messages' )
			expect( response.data ).toEqual( {} )

			return;
			
		});

		test('3. Requesting non-existent message', done => {

			http.get( 'http://127.0.0.1:3000/messages/1', response => {

				expect( response.statusCode ).toBe( 404 )
				done()

			})
		});

		test('4. Adding first message', async () => {

			const response = await post( 'http://127.0.0.1:3000/messages', { body: { text: 'First message' } } )
			expect( response.data ).toEqual( { _id: 1, text: 'First message' } )

			const messages = await get( 'http://127.0.0.1:3000/messages' )
			expect( messages.data ).toEqual( { 1: { _id: 1, text: 'First message' } } )

			return;
			
		});

		test('5. Updating message', async () => {

			const response = await put( 'http://127.0.0.1:3000/messages/1', { body: { _id: 1, text: 'Updated message' } } )
			expect( response.data ).toEqual( { _id: 1, text: 'Updated message' } )

			const messages = await get( 'http://127.0.0.1:3000/messages' )
			expect( messages.data ).toEqual( { 1: { _id: 1, text: 'Updated message' } } )

			return;
			
		});

		test('6. Updating non-existent message', async () => {

			try {
				const response = await put( 'http://127.0.0.1:3000/messages/2', { body: { _id: 2, text: 'Updated non-existent message' } } )
			}
			catch ( error ) {
				expect( error.statusCode ).toBe( 404 )
			}
			
			const messages = await get( 'http://127.0.0.1:3000/messages' )
			expect( messages.data ).toEqual( { 1: { _id: 1, text: 'Updated message' } } )

			return;
			
		});

		test('7. Patching message', async () => {

			const response = await patch( 'http://127.0.0.1:3000/messages/1', { body: { status: 'read' } } )
			expect( response.data ).toEqual( { _id: 1, text: 'Updated message', status: 'read' } )

			const messages = await get( 'http://127.0.0.1:3000/messages' )
			expect( messages.data ).toEqual( { 1: { _id: 1, text: 'Updated message', status: 'read' } } )

			return;
			
		});

		test('8. Deleting message', async () => {

			const response = await del( 'http://127.0.0.1:3000/messages/1' )
			expect( response.data ).toEqual( { _id: 1, text: 'Updated message', status: 'read' } )

			const messages = await get( 'http://127.0.0.1:3000/messages' )
			expect( messages.data ).toEqual( {} )

			return;
			
		});

		test('9. Ensuring sequential IDs', async () => {

			const response = await post( 'http://127.0.0.1:3000/messages', { body: { text: 'Second message' } } )
			expect( response.data ).toEqual( { _id: 2, text: 'Second message' } )

			const messages = await get( 'http://127.0.0.1:3000/messages' )
			expect( messages.data ).toEqual( { 2: { _id: 2, text: 'Second message' } } )

			return;
			
		});

		

	});

	describe('Hooks unit tests with fake "users" API', () => {

		test('1. Creating a user, with "before" and "after" hooks', async () => {

			const response = await post( 'http://127.0.0.1:3000/users', { body: { email: 'user@provider.com', password: 'test123' } } )
			expect( response.data ).toEqual( { _id: 1, email: 'user@provider.com', newField: 'New field' } )

			const users = await get( 'http://127.0.0.1:3000/users' )
			expect( users.data ).toEqual( { 1: { _id: 1, email: 'user@provider.com', newField: 'New field' } } )

			return;
			
		});

	});

	describe('Testing error output on responses', () => {

		test('1. Basic error on service', async () => {

			try {
				const response = await get( 'http://127.0.0.1:3000/errors' )
			}
			catch ( error ) {
				expect( error.data ).toEqual( {
					// "originalColumn": 20,
					// "originalLine": 6,
					"name": "BadRequest",
					"message": "Test message",
					"code": 400
				})
				expect( error.statusCode ).toBe( 400 )
			}

			return;
			
		});

	});


});