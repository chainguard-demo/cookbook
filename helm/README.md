# Helm

## List images in chart

```sh
helm template <image> | grep -oE 'image: .+' | cut -d' ' -f2 | sort | uniq | tr -d '"'
```
