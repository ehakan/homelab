# Local Experimentation Environment

## Getting Started

1. Create pull through cache image registries

    ```sh
    $ docker-compose up -d
    ```

    This will create 4 container image registries for the main public repositories.
2. Create the talos cluster

    ```sh
    $ ./create-cluster.sh
    ```

    Make sure to delete the old cluster with `talosctl cluster destroy`

## Things to do & document

- [ ] Mainstreamed patches
- [ ] Cluster bootstrapping
