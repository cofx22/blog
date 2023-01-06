Title: Sending Data to the Other Side of the World: JSON vs Protocol Buffers and REST vs gRPC
Date: 2019-02-19
Tags: gRPC, Protocol buffers
Canonical-URL: https://www.kabisa.nl/tech/sending-data-to-the-other-side-of-the-world-json-protocol-buffers-rest-grpc

*This post first appeared on [Kabisa's Tech Blog](https://www.kabisa.nl/tech/).*

For a project I’m working on,
I wanted to know which protocol and data representation would be best to transfer relatively large amounts of data between microservices.
At first, I just wanted to see whether using [protocol buffers](https://developers.google.com/protocol-buffers/) to represent data would lead to smaller response sizes compared to compressed JSON.
Once I was looking into protocol buffers,
I wondered when it would be better to choose [gRPC](https://grpc.io/) over REST.

## Protocol Buffers

As [Google puts it](https://developers.google.com/protocol-buffers/),
protocol buffers are a language-neutral, platform-neutral extensible mechanism for serializing structured data.
Given the definition below,
code to efficiently serialize and deserialize compact representations of lists of vectors can be generated for a number of programming languages.

```protobuf
syntax = "proto3";

package vectors;

message Point {
    double x = 1;
    double y = 2;
    double z = 3;
}

message Vector {
    Point start = 1;
    Point end = 2;
}

message Vectors {
    repeated Vector vectors = 1;
}
```

As you can see in the definition above, the data is typed.
That is an advantage over JSON if you ask me.
Because of the large number of supported programming languages, you can exchange protocol buffers between apps written in many languages.

## gRPC

[gRPC](https://grpc.io/) is a high-performance, open-source universal framework for remote procedure calls.
If you extend the definition above with declarations like the ones below,
code can be generated that allows client applications to call methods of server applications in a way that compares to calling local methods.

```protobuf
service VectorService {
    rpc GetVectorStream(VectorsRequest) returns (stream Vector) {}
    rpc GetVectors(VectorsRequest) returns (Vectors) {}
}

message VectorsRequest {
    int64 seed = 1;
    int32 number_of_vectors = 2;
}
```

You implement the actual service by extending the base implementation generated from the definition.
The following code shows an example implementation in Java.

```java
@GRpcService
public class VectorsService extends VectorServiceGrpc.VectorServiceImplBase {

    private final VectorGenerator vectorGenerator;

    @Autowired
    public VectorsService(VectorGenerator vectorGenerator) {
        this.vectorGenerator = vectorGenerator;
    }

    @Override
    public void getVectors(VectorProto.VectorsRequest request, StreamObserver<VectorProto.Vectors> responseObserver) {
        responseObserver.onNext(toProto(vectorGenerator.generateRandomVectors(request.getSeed(), request.getNumberOfVectors())));
        responseObserver.onCompleted();
    }

    @Override
    public void getVectorStream(VectorProto.VectorsRequest request, StreamObserver<VectorProto.Vector> responseObserver) {
        vectorGenerator.generateRandomVectors(request.getSeed(), request.getNumberOfVectors()).forEach(vector -> responseObserver.onNext(toProto(vector)));
        responseObserver.onCompleted();
    }
}
```

The following implementation of a consumer gives an example of how such a remote procedure is called by a client.

```java
@Component
public class VectorsServiceConsumer {

    public void getVectors(String hostname, int port, long seed, int numberOfVectors) {
        var managedChannel = ManagedChannelBuilder.forAddress(hostname, port).usePlaintext().build();
        var blockingStub = VectorServiceGrpc.newBlockingStub(managedChannel);
        var vectorsRequest = VectorProto.VectorsRequest.newBuilder()
                .setNumberOfVectors(numberOfVectors)
                .setSeed(seed)
                .build();

        var response = blockingStub.getVectors(vectorsRequest);

        response.getVectorsList();

        managedChannel.shutdown();
    }

    public void getVectorStream(String hostname, int port, long seed, int numberOfVectors) {
        var managedChannel = ManagedChannelBuilder.forAddress(hostname, port).usePlaintext().build();
        var blockingStub = VectorServiceGrpc.newBlockingStub(managedChannel);
        var vectorsRequest = VectorProto.VectorsRequest.newBuilder()
                .setNumberOfVectors(numberOfVectors)
                .setSeed(seed)
                .build();

        var response = blockingStub.getVectorStream(vectorsRequest);

        while (response.hasNext()) {
            response.next();
        }

        managedChannel.shutdown();
    }
}
```

## Some Experiments
To see some practical results and learn about the implementation details,
I created a Spring Boot application that sends and receives data via REST and gRPC. If you want to do your own experiments, you could use that app as a starting point:

<https://github.com/ljpengelen/RPC>

The data exchanged by this app is a list of vectors with random start and end points. Represented as JSON, a vector looks as follows.

```json
{
  "start": {
    "x": 0.730967787376657,
    "y": 0.24053641567148587,
    "z": 0.6374174253501083
  },
  "end": {
    "x": 0.5504370051176339,
    "y": 0.5975452777972018,
    "z": 0.3332183994766498
  }
}
```

## Response Size

The table below shows the response size in kilobytes when requesting a list of vectors of a given size via REST,
using three different representations.
As you can see from the table, if compression of responses is enabled on the server,
it doesn’t matter much whether you choose for JSON or protocol buffers to represent your data.
As far as response size is concerned, you might as well keep things simple and stick with JSON.

One reason to prefer protocol buffers over compressed JSON would be that protocol buffers are typed.
Additionally, if you use a framework such as Spring Boot, you have to define [data transfer objects](https://en.wikipedia.org/wiki/Data_transfer_object) to represent the requests and responses of your REST endpoints.
With protocol buffers, these are generated for you.

| Number of vectors | JSON  | Compressed JSON  | Protocol Buffers |
| ----------------: | ----: | ---------------: | ---------------: |
| 1.000             | 156   | 59               | 59               |
| 10.000            | 1.520 | 576              | 586              |
| 100.000           | 15.220| 5.600            | 5.720            |

## Speed

To compare the amount of time it takes to exchange lists of vectors via REST and gRPC,
I’ve set up two virtual machines on AWS.
Both machines had type `t2.small` (<https://aws.amazon.com/ec2/instance-types/>) and ran Linux and Java 11.
One was located in Frankfurt and the other in Sydney.
I was communicating with these machines from my local machine in Eindhoven,
a 2017 MacBook Pro with a 2.8 GHz Intel Core i7 processor and 16 GB of RAM.

The table below shows the amount of time in milliseconds it takes to retrieve a list (or stream) of 10.000 vectors 10 times in a row.
The two columns labelled “REST” show how much time it takes to exchange data represented as JSON and protocol buffers.
With gRPC, data is always represented as protocol buffers.
The two columns labelled “gRPC” show how much time it takes to transfer multiple vectors as a list and as a stream.

| Client    | Server    | REST JSON | REST Protobuf | gRPC List | gRPC Stream |
| :-------- | :-------- | --------: | ------------: | --------: | ----------: |
| Eindhoven | Eindhoven | 326       | 77            | 118       | 1.764       |
| Eindhoven | Frankfurt | 883       | 665           | 1.689     | 2.430       |
| Eindhoven | Sydney    | 16.161    | 11.658        | 55.457    | 57.537      |
| Frankfurt | Sydney    | 6.531     | 4.930         | 22.730    | 22.864      |
| Sydney    | Frankfurt | 7.276     | 4.589         | 22.745    | 26.161      |
| Frankfurt | Frankfurt | 980       | 170           | 287       | 1.120       |
| Sydney    | Sydney    | 1.021     | 257           | 368       | 1.189       |

The last three rows are included as a sort of sanity check.
I would expect the numbers for `Frankfurt -> Frankfurt` to be comparable to those for `Sydney -> Sydney` (because we’re essentially doing the exact same thing) and a little worse than those for `Eindhoven -> Eindhoven` (because my laptop is faster than the ec2 instances).
This seems to be the case.
I would also expect `Frankfurt -> Sydney` to be comparable to `Sydney -> Frankfurt`, which is also the case.

The results might give the impression that there’s little reason to prefer gRPC over REST.
This is caused by the fact that we’re not using gRPC to its fullest potential.
For this experiment, we’re using blocking communication and don’t process the stream of vectors vector by vector.
In real-world scenarios, however, it might be benificial to use asynchronous communication,
and deal with input and output as streams.

## Conclusion

To conclude, here are some bullet points with simplistic advice:

* If you only care about response size, use REST and JSON, enable compression, and call it a day.
* If you want your data to be typed and keep things simple, use REST and protocol buffers.
* If you want to handle your input and output as streams, use gRPC.
