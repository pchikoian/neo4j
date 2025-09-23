# Neo4j

[Neo4j](https://neo4j.com/) is a graph database management system that allows you to store, retrieve and query graph data efficiently.

## TL;DR

```console
helm install my-release ./neo4j-helm
```

## Introduction

This chart bootstraps a [Neo4j](https://github.com/neo4j/neo4j) cluster deployment on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- PV provisioner support in the underlying infrastructure

## Installing the Chart

To install the chart with the release name `my-release`:

```console
helm install my-release ./neo4j-helm
```

The command deploys Neo4j on the Kubernetes cluster in the default configuration. The [Parameters](#parameters) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```console
helm delete my-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Parameters

### Global parameters

| Name                      | Description                                     | Value |
| ------------------------- | ----------------------------------------------- | ----- |
| `global.imageRegistry`    | Global Docker image registry                    | `""`  |
| `global.imagePullSecrets` | Global Docker registry secret names as an array| `[]`  |
| `global.storageClass`     | Global StorageClass for Persistent Volume(s)   | `""`  |

### Common parameters

| Name                | Description                                        | Value |
| ------------------- | -------------------------------------------------- | ----- |
| `nameOverride`      | String to partially override common.names.name    | `""`  |
| `fullnameOverride`  | String to fully override common.names.fullname    | `""`  |
| `commonLabels`      | Labels to add to all deployed objects             | `{}`  |
| `commonAnnotations` | Annotations to add to all deployed objects        | `{}`  |

### Neo4j Image parameters

| Name                | Description                          | Value               |
| ------------------- | ------------------------------------ | ------------------- |
| `image.registry`    | Neo4j image registry                | `docker.io`         |
| `image.repository`  | Neo4j image repository              | `neo4j`             |
| `image.tag`         | Neo4j image tag                     | `5.15.0-enterprise` |
| `image.pullPolicy`  | Neo4j image pull policy             | `IfNotPresent`      |
| `image.pullSecrets` | Neo4j image pull secrets            | `[]`                |

### Neo4j Configuration parameters

| Name              | Description                                    | Value |
| ----------------- | ---------------------------------------------- | ----- |
| `replicaCount`    | Number of Neo4j replicas to deploy           | `3`   |
| `configuration`   | Neo4j configuration parameters                | `{}`  |

### Authentication parameters

| Name                              | Description                                   | Value        |
| --------------------------------- | --------------------------------------------- | ------------ |
| `auth.enabled`                    | Enable authentication                        | `true`       |
| `auth.neo4jPassword`              | Password for the neo4j user                 | `"neo4j123"` |
| `auth.existingSecret`             | Name of existing secret containing password  | `""`         |
| `auth.existingSecretPasswordKey`  | Password key in existing secret              | `""`         |

### Traffic Exposure Parameters

| Name                    | Description                          | Value       |
| ----------------------- | ------------------------------------ | ----------- |
| `service.type`          | Neo4j service type                   | `ClusterIP` |
| `service.ports.bolt`    | Neo4j service Bolt port              | `7687`      |
| `service.ports.http`    | Neo4j service HTTP port              | `7474`      |
| `service.ports.cluster` | Neo4j service cluster port           | `5000`      |

### Persistence Parameters

| Name                        | Description                          | Value                |
| --------------------------- | ------------------------------------ | -------------------- |
| `persistence.enabled`       | Enable persistence using PVC        | `true`               |
| `persistence.storageClass`  | PVC Storage Class                    | `""`                 |
| `persistence.accessModes`   | PVC Access Modes                     | `["ReadWriteOnce"]`  |
| `persistence.size`          | PVC Storage Request                  | `10Gi`               |

## Configuration and installation details

### Cluster Configuration

This chart creates a Neo4j cluster using StatefulSet with the following characteristics:

- **Default replica count**: 3 (minimum for cluster quorum)
- **Cluster discovery**: Uses Kubernetes service discovery
- **Persistent storage**: Each pod gets its own PersistentVolume
- **Pod management**: Parallel pod management for faster startup

### Authentication

By default, authentication is enabled with:
- Username: `neo4j`
- Default password: `neo4j123`

You can customize the password by setting `auth.neo4jPassword` or use an existing secret.

### Persistence

The chart mounts a [Persistent Volume](http://kubernetes.io/docs/user-guide/persistent-volumes/) at the `/data` path. The volume is created using dynamic volume provisioning.

### Cluster Communication

The chart creates two services:

1. **Regular Service**: For client connections (Bolt and HTTP)
2. **Headless Service**: For inter-cluster communication and service discovery

## Troubleshooting

### Pods are not starting

Check the following:

1. **Storage**: Ensure your cluster has a default StorageClass or specify one
2. **Resources**: Verify your cluster has enough CPU and memory
3. **Replica count**: Must be at least 3 for cluster formation

### Cluster is not forming

1. Check that all pods are in Ready state
2. Verify the headless service is created correctly
3. Check pod logs for connection errors

### Accessing the database

To get connection details:

```console
# Get the password
export NEO4J_PASSWORD=$(kubectl get secret <release-name> -o jsonpath="{.data.neo4j-password}" | base64 --decode)

# Port forward to access locally
kubectl port-forward svc/<release-name> 7474:7474 7687:7687
```

## Examples

### Minimal installation

```yaml
# values-minimal.yaml
auth:
  neo4jPassword: "mypassword"
replicaCount: 3
```

### Production-ready setup

```yaml
# values-production.yaml
replicaCount: 3

resources:
  requests:
    memory: "2Gi"
    cpu: "1"
  limits:
    memory: "4Gi"
    cpu: "2"

persistence:
  size: 50Gi
  storageClass: "ssd"

configuration:
  dbms.memory.heap.initial_size: "1G"
  dbms.memory.heap.max_size: "2G"
  dbms.memory.pagecache.size: "1G"

auth:
  neo4jPassword: "secure-password"
```