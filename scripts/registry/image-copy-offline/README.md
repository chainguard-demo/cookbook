# image-copy-offline

Script to copy images to an offline registry where the only dependency is `crane`. 

## Usage

> [!NOTE]
> If you are on a Mac and don't have `flock` the file lockng section of the script will be ignored.

### Pull images locally and store on fs
`./copy.sh pull -f images.txt`

### Push images to the registry defined
`./copy.sh push -f images.txt

### Pull images locally and push in one command
`./copy.sh full -f images.txt`


## Input file format

The input file is an = delimited key value pair. The first part is the upstream image name, and the second part is the local registry name.

`cgr.dev/foo.com/go:latest=localhost:5000/go:newtag`

## Testing

1. Run `crane registry serve --address localhost:5000`
2. Run `./copy.sh full -f input.txt`


