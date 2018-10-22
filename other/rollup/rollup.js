import commonjs 	from 'rollup-plugin-commonjs';
import json 		from 'rollup-plugin-json';
import resolve 		from 'rollup-plugin-node-resolve';

export default {
	input: 'framework/altiva.js',

	external: [
		'buffer',
		'events',
		'fs',
		'http',
		'net',
		'path',
		'querystring',
		'stream',
		'string_decoder',
		'tty',
		'util',
		'zlib'
	],

	output: {
		file: 'altiva.js',
		format: 'cjs',
		name: 'Altiva',
	},

	plugins: [
		json(),
		resolve( {
			jsnext: true
		} ),
		commonjs()
	]
};