# Alumna Backend: Towards a software architecture that is easier, technology agnostic and future-proof

![npm](https://img.shields.io/npm/v/@alumna/backend.svg) ![npm](https://img.shields.io/npm/dt/@alumna/backend.svg) 

Alumna Backend is a NodeJS/Bun **back-end framework** which is the first implementation of a new software architecture concept, which provides abstraction of all layers involved, including protocols.

It is the first experiment based on a variation of continuous passing style, present on many frameworks like Express, but heavily inspired by FeathersJS, but recreating the internals from scratch as well as leaving the call stack linear, implementing a "linear continuous passing style" concept.

## Install and basic usage

### Step 1

Install it using your prefered package manager. The command below considers `npm`:

```
npm install @alumna/backend
```

### Step 2

Import the library and create the endpoints:

```
// import the library
import Alumna from '@alumna/backend';

// import services types, e.g.
import MysqlService from './services/MysqlService.js'
import MemoryService from './services/MemoryService.js'

// import hooks (application and business rules), e.g.
import UserHooks from './hooks/UserHooks'

//
// create a instance for your backend
const backend = new Alumna();

// create as many services as you want
backend.use( 'users', new MysqlService() )
backend.use( 'tasks', new MysqlService() )
backend.use( 'messages', new MemoryService() )

// apply as many hooks as you want
backend.service( 'users' ).hooks( UserHooks )

//
// start listening for requests
backend.listen()
```

## Service API

You can implement just the methods you want

```js
class ExampleService {
	
	constructor() {}

	async find () {}

	async get( id, params ) {}

	async create ( data ) {}

	async update( id, data ) {}
	
	async patch( id, data ) {}
	
	async remove( id ) {}

	async setup ( app, path ) {}

}

export default ExampleService;
```

## Hook API

Hooks are created to apply application or business rules to one or more services (or even the whole application, when its the case)

```js
import exampleHook from './hooks/example.js'
import anotherHook from './hooks/another.js'
import errorHook from './hooks/error.js'

export default {
	before: {
		all: [],
		find: [ exampleHook ],
		get: [ anotherHook, exampleHook ],
		create: [],
		update: [],
		patch: [],
		remove: []
	},

	after: {
		all: [],
		find: [],
		get: [],
		create: [],
		update: [],
		patch: [],
		remove: []
	},

	error: {
		all: [ errorHook ],
		find: [],
		get: [],
		create: [],
		update: [],
		patch: [],
		remove: []
	}
};
```

## Roadmap

**Site and documentation**
- [x] Create basic documentation on README
- [ ] Create website
- [ ] Create complete documentation on website