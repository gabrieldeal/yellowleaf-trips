module.exports = {
  module: {
    rules: [
      {
        test: /\.(png|jpg|gif|svg)$/,
        use: [
          {
            loader: 'file-loader',
            options: {
              publicPath: '../js',
            }
          }
        ]
      },
      {
        test: /\.css$/,
        use: [ 'style-loader', 'css-loader' ]
      }
    ],
  },
  entry: {
    main: './src/index.js',
    async: './src/async.js'
  },
  output: {
    filename: '[name].js',
    library: 'Yellowleaf_[name]',
    libraryTarget: 'window'
  },
}
