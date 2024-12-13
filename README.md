# [tinygrad](https://github.com/tinygrad/tinygrad) host for iOS

Run tinygrad models using your iPhone or iPad's GPU

## steps
1. install and open this app on your iPhone or iPad
2. install [tinygrad](https://github.com/tinygrad/tinygrad) on a computer connected to the same wifi network

3. run any tinygrad code
```sh
CLOUD=1 HOST={your iphone/ipad IP address}:6667 python3 examples/gpt2.py --model_size=gpt2
```
## notes
- Max allowed app RAM < total RAM. An iPhone 13 (4GB RAM) cannot use over 2GB in a single app for example, it will crash. Each device has its own limit.
- Metal cannot be ran in the background on iOS, the app must be open to run.
- Modifying one line in tinygrad to send batches on copyin() can increase the the amount of memory that can be used, depending on the situation. This needs to be fixed within this app.
