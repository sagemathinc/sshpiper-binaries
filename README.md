# sshpiper binaries with REST plugin

[**sshpiper**](https://github.com/tg123/sshpiper) is a reverse proxy for sshd. All protocols, including ssh, scp, port forwarding, and running commands on top of ssh are fully supported.

This repo publishes a recipe for sshpiper binaries, built from [upstream](https://github.com/tg123/sshpiper) and including only the [REST plugin](https://github.com/11notes/docker-sshpiper). The REST plugin is by far the most flexible and useful, but it is not officially included upstream.

## Contents

Each release provides a tarball per platform, named like:

```
sshpiper-v<version>-<os>-<arch>.tar.xz
```

For example:

```
sshpiper-v1.5.0-linux-amd64.tar.xz
```

Extracting it yields a versioned directory:

```
sshpiper-v1.5.0-linux-amd64/
  sshpiperd
  sshpiperd-rest
```

To install, copy both files somewhere on your `PATH`, e.g.:

```sh
sudo cp sshpiperd* /usr/local/bin/
```

## Tutorial

Suppose you have two ssh servers on localhost at ports 3089 and 5077. You can connect to them directly via:

```sh
ssh user@localhost -p 3089
ssh user@localhost -p 5077
```

The following Node.js script creates a simple HTTP server. With it, connecting as `ssh test@localhost -p 2222` will proxy to port 3089, while any other username (e.g. `ssh anything-but-test@localhost -p 2222`) will proxy to port 5077.

**Key flow:**

- `authorizedKeys`: controls which _client_ keys are accepted by sshpiper.
- `privateKey`: is the identity sshpiper uses to log into the _upstream_ server. This mapping step is why sshpiper must terminate and re-encrypt SSH traffic.

```js
// server.js
import express from "express";
import fs from "fs";

const app = express();
app.use(express.json());

function portForProject(id) {
  if (id == "test") {
    return 3089;
  }
  return 5077;
}

app.get("/auth/:id", (req, res) => {
  // authorizedKeys = how we trust incoming connections to sshpiper
  const authorizedKeys = fs.readFileSync("authorized_keys", "utf8");
  // privateKey = how sshpiper connects out to upstream
  const privateKey = fs.readFileSync("ed25519", "utf8");

  const { id } = req.params;
  const port = portForProject(id);

  res.json({
    user: "user",
    host: `127.0.0.1:${port}`,
    authorizedKeys,
    privateKey,
  });
});

app.listen(8443, () =>
  console.log("sshpiper auth @ http://127.0.0.1:8443/auth/:id"),
);
```

To run the above, you need Express. Install it globally, or add it as a dependency in a project:

```sh
npm install express
```

You also need to make the private key `ed25519` mentioned in the code:

```sh
ssh-keygen -t ed25519 -f ed25519 -P ""
```

Put `ed25519.pub` into the `authorized_keys` file for the two ssh servers running locally on ports 3089 and 5077, so sshpiperd can connect upstream without a password.

Once it is running, start sshpiperd as follows:

```sh
./sshpiperd \
  -i server_host_key \
  --server-key-generate-mode notexist \
  ./sshpiperd-rest --url http://127.0.0.1:8443/auth
```

## Build Reproducibility

Binaries are built by [build.sh](./build.sh) and GitHub Actions workflows in this repo. You can rerun the same process yourself to verify results.

## Notes

- These builds are intended for lightweight use in containers or resource\-constrained environments.
- Changes to `authorized_keys` are picked up on the next connection attempt; no restart of sshpiperd is required.
- Treat your REST service as part of your security boundary: bind it to localhost or firewall it appropriately. Anyone who can hit `/auth` can potentially control sshpiper’s routing/auth decisions.
