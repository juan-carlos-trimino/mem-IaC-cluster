# The application and its microservices

This application is based on xxxxxxxx. It is composed of sssss microservices; vis., `a`, `b`, `c`, and `d`.
The app contains a single RabbitMQ server instance; the RabbitMQ server contains multiple queues
  with different names.
Each microservice has its own private database; the databases are hosted on a shared server.

***
<br>

# Gateway/Reverse Proxy (mem-gateway)

The gateway is the entry point to the app; it provides a REST API so the front end can interact with the backend.

***
<br>

# History (mem-history)

It records the user's viewing history.

video-streaming -> RabbitMQ('viewed' message) -> history -> mongoDB('history' db)


(1) 'viewed' message is how the video-streaming microservice informs the history microservice
     that the user has watched a video.
(2) The history microservice receives messages from the video-streaming microservice, and it
    records them in its own database.

***
<br>

# Metadata (mem-metadata)

It records details and metadata about each video.

* The app contains a single RabbitMQ server instance; the RabbitMQ server contains multiple queues
  with different names.
* Each microservice has its own private database; the databases are hosted on a shared server.

***
<br>

# RabbitMQ (mem-rabbitmq)

***
<br>

# Video-Storage (mem-video-storage)

An abstraction of the file storage provider. One advantage of this architecture (separation of concerns and single responsibility principle) is that the video storage microservice can be easily swapped out and be replaced with an alternative.

#### `Note`
IBM's Cloud Object Storage (COS) is `S3` (Simple Storage Service) compatible and can, thus, be used with any S3-compatible tooling. The fundamental unit of object storage is called a `bucket`.

***
<br>

# Video-Streaming (mem-video-streaming)

It streams videos from storage to be watched by the user.

external cloud storage -> video-storage -> video-streaming -> gateway -> user UI
                                                |
                         												-> RabbitMQ (viewed message) -> history

***
<br>

# Video-Upload (mem-video-upload)

It orchestrates upload of videos to storage.


user UI -> gateway -> video-upload -> video-storage -> external cloud storage
                           |
                           -> RabbitMQ (uploaded message) -> metadata








RESOURCEGROUP=Default
COS_NAME_RANDOM=$(date | md5sum | head -c10)
COS_NAME=$COS_NAME_RANDOM-cos-1
COS_CREDENTIALS=$COS_NAME-credentials
COS_PLAN=Lite
COS_BUCKET_NAME=$(date | md5sum | head -c10)-bucket-1
REGION=us-south
COS_PRIVATE_ENDPOINT=s3.private.$REGION.cloud-object-storage.appdomain.cloud



emptyDir
An emptyDir volume is first created when a Pod is assigned to a node, and exists as long as that Pod is running on that node. As the name says, the emptyDir volume is initially empty. All containers in the Pod can read and write the same files in the emptyDir volume, though that volume can be mounted at the same or different paths in each container. When a Pod is removed from a node for any reason, the data in the emptyDir is deleted permanently.
Note: A container crashing does not remove a Pod from a node. The data in an emptyDir volume is safe across container crashes.



Data is available to all nodes within the availability zone where the file storage exists, but the accessMode parameter on the PersistentVolumeClaim determines if multiple pods are able to mount a volume specificed by a PVC. The possible values for this parameter are:

ReadWriteMany: The PVC can be mounted by multiple pods. All pods can read from and write to the volume.
ReadOnlyMany: The PVC can be mounted by multiple pods. All pods have read-only access.
ReadWriteOnce: The PVC can be mounted by one pod only. This pod can read from and write to the volume.

