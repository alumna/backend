import commonjs 	from '@rollup/plugin-commonjs';
import json 		from '@rollup/plugin-json';
import resolve 		from '@rollup/plugin-node-resolve';
import { terser } 	from 'rollup-plugin-terser';

export default {
	input: 'src/alumna.js',

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
		file: 'dist/alumna.cjs.js',
		format: 'cjs',
		name: 'Alumna',
	},

	plugins: [
		json(),
		resolve(),
		commonjs(),
		terser()
	]
};