Title: Experimenting with MongoDB index creation and Spring Boot
Date: 2023-03-29
Tags: Java, Spring, MongoDB
Image: assets/social/cofx-java.png
Image-Alt: An image indicating that this post is about Java
Issue: 7

Creating indexes for MongoDB collections with Spring Boot is easy.
You annotate your entities with the correct annotations,
you set `spring.data.mongodb.auto-index-creation` to `true` in your configuration file, and you're done.
Indexes will be created when you start your application.

Over time, however, people will start using your application, and your MongoDB collections will grow as a result.
Creating an index for an empty collections takes very little time.
Creating an index for a big collection can take a while.
Because of this, configuring Spring to handle index creation on startup can lead to unpleasant surprises.
The startup of your application will block until the new index is created, and this can take a while for existing, large collections.

Additionally, your application will not start at all if something goes wrong while creating an index.
This could happen if you try to modify an existing index, for example.

All in all, it's worthwhile to take a closer look at various ways to programmatically create, find, and delete indexes.

<!-- end-of-preview -->

## Experimenting

I've created a small Spring Boot application accompanied by a set of tests to experiment with index creation: <https://github.com/ljpengelen/mongo-index-experiments>.
The application itself is not much more than a single document `RandomData` and a repository for this document.
The class `RandomData` looks like this:

```java
@Builder
@CompoundIndex(def = "{ randomString: 1, randomLong: 1 }", name = "idx0")
@Data
@Document
public class RandomData {

    @Indexed
    private String randomString;

    @Indexed
    private long randomLong;

    private boolean randomBoolean;
}
```

The app is configured to create indexes on startup, so once you start it, four indexes are generated:
one compound index corresponding to the `@CompoundIndex` annotation,
two single-field indexes corresponding to the `@Indexed` annotations,
and one for the implicit ID.
On my machine, the app starts in about 2 seconds.
Part of the startup time is spent creating indexes, but this is almost negligible.

Now, let's insert some random data by executing the following test a few times:

```java
@Test
void savesEntities() {
    var batchSize = 100;
    var totalNumberOfEntities = 1_000_000;
    IntStream.range(0, totalNumberOfEntities / batchSize).forEach(batchNumber -> {
        var entities = Stream.generate(ExperimentApplicationTest::randomData)
                .limit(batchSize)
                .toList();
        repository.saveAll(entities);

        if (batchNumber % 500 == 0) {
            log.info("Inserting batch number {}", batchNumber);
        }
    });
}
```

After inserting 3 million documents and removing the previously created indexes,
the app takes around 14 seconds to start on my machine.
Clearly, the time it takes to create indexes is no longer negligible.

Now that I've told you the same thing twice, it's time for some new information.

One way of creating indexes programmatically uses Spring's Mongo template:

```java
@Test
void createsIndexViaTemplate() {
    var indexOps = mongoTemplate.indexOps(COLLECTION_NAME);

    log.info("Creating index");

    var indexDefinition = new Index();
    indexDefinition.named(INDEX_NAME)
            .on("randomBoolean", Sort.Direction.ASC)
            .on("randomString", Sort.Direction.ASC)
            .on("randomLong", Sort.Direction.ASC);

    var stopWatch = new StopWatch();
    stopWatch.start();
    indexOps.ensureIndex(indexDefinition);
    stopWatch.stop();
    log.info("Time to create index: {}", stopWatch.getTotalTimeMillis());
}
```

On my machine, creating this index takes around 4 seconds.

With MongoDB versions before 4.2,
indices could be created in the foreground or the background.
Foreground builds would be faster and would lead to more efficient index data structures,
but would block access to the database during the build.
Background builds would not block access to the database,
but would take longer to build and be less efficient.

Starting from version 4.2,
access is no longer blocked while the index is built.
However, access is blocked at the start and end of the build process.

Even though access to the database is not blocked during index creation,
the statement `indexOps.ensureIndex(indexDefinition)` does block,
just like the application startup blocks during index creation.

One way of ensuring that your application is not blocked during index creation is by explicitly starting a new thread for this:

```java
@Test
void createsIndexViaTemplateInBackground() throws InterruptedException, ExecutionException {
    var indexOps = mongoTemplate.indexOps(COLLECTION_NAME);

    var completableFuture = new CompletableFuture<Void>();
    var thread = new Thread(() -> {
        log.info("Creating index");

        var indexDefinition = new Index();
        indexDefinition.named(INDEX_NAME)
                .on("randomBoolean", Sort.Direction.ASC)
                .on("randomString", Sort.Direction.ASC)
                .on("randomLong", Sort.Direction.ASC);

        var stopWatch = new StopWatch();
        stopWatch.start();
        indexOps.ensureIndex(indexDefinition);
        stopWatch.stop();
        log.info("Time to create index: {}", stopWatch.getTotalTimeMillis());

        completableFuture.complete(null);
    });

    thread.start();

    completableFuture.get();
}
```

Alternatively, you could use Spring's reactive Mongo template:

```java
@Test
void createsIndexReactively() throws InterruptedException, ExecutionException {
    var indexOps = reactiveMongoTemplate.indexOps(COLLECTION_NAME);

    log.info("Creating index");

    var indexDefinition = new Index();
    indexDefinition.named(INDEX_NAME)
            .on("randomBoolean", Sort.Direction.ASC)
            .on("randomString", Sort.Direction.ASC)
            .on("randomLong", Sort.Direction.ASC);

    var completableFuture = new CompletableFuture<Void>();
    var stopWatch = new StopWatch();
    stopWatch.start();
    indexOps.ensureIndex(indexDefinition).subscribe(name -> {
        stopWatch.stop();
        log.info("Time to create index {}: {}", name, stopWatch.getTotalTimeMillis());

        completableFuture.complete(null);
    });

    completableFuture.get();
}
```

If you're looking for a way to create indexes that is not Spring-specific, you could also use the Mongo client for Java:

```java
@Test
void createsIndexViaClient() {
    var keys = new BsonDocument();
    keys.put("randomLong", new BsonInt32(1));
    keys.put("randomString", new BsonInt32(1));
    keys.put("randomBoolean", new BsonInt32(1));

    var indexOptions = new IndexOptions();
    indexOptions.name(INDEX_NAME);

    var stopWatch = new StopWatch();
    stopWatch.start();
    log.info("Creating index");
    mongoClient.getDatabase(DATABASE_NAME).getCollection(COLLECTION_NAME).createIndex(keys, indexOptions);
    stopWatch.stop();
    log.info("Time to create index: {}", stopWatch.getTotalTimeMillis());
}
```

The statement `mongoClient.getDatabase(...).getCollection(...).createIndex(keys, indexOptions)` is again a blocking statement.
As you might expect, all four ways take the same amount of time to create this particular index.
The hard work is done by MongoDB, not our application or any library we're using.

## What's in a name?

Some of the methods above are named `ensureIndex`, and some are named `createIndex`.
In practice, they all behave as you would expect a method named `ensureIndex` to behave.
They create an index if it doesn't exist yet, and they'll just do nothing if the index is already present.
In other words, the following test passes and the last `indexOps.ensureIndex(indexDefinition)` only takes a few milliseconds:

```java
@Test
void canEnsureExistingIndexViaTemplate() {
    var indexOps = mongoTemplate.indexOps(COLLECTION_NAME);

    var indexDefinition = new Index();
    indexDefinition.named(INDEX_NAME)
            .on("randomBoolean", Sort.Direction.ASC)
            .on("randomString", Sort.Direction.ASC)
            .on("randomLong", Sort.Direction.ASC);

    log.info("Ensuring index");
    indexOps.ensureIndex(indexDefinition);
    log.info("Ensured index");
    indexOps.ensureIndex(indexDefinition);
    log.info("Ensured index again");
}
```

## No updates

MongoDB does not allow you to update existing indices.
If you have a non-unique index with a given name and you want a unique index with that same name,
for example,
you have to delete the existing index and create a new one to replace it.
After deleting the existing index, performance may suffer until the replacement index is built.

Alternatively, you can introduce the replacement index with a new name.
It's perfectly fine to have two indexes for the same fields as long as they have different names and one is unique and the other isn't,
or one is sparse and the other isn't, etc.

## Automating index creation

A basic way of creating indexes at the start of your application, without blocking, is as follows:

```java
@Component
@Slf4j
public class RandomDataIndexCreator {

    private static final String COLLECTION_NAME = "randomData";
    private static final String DATABASE_NAME = "test";
 
    private final MongoIndexOperations mongoIndexOperations;

    public RandomDataIndexCreator(MongoClient mongoClient) {
        mongoIndexOperations = new MongoIndexOperations(DATABASE_NAME, COLLECTION_NAME, mongoClient);
    }

    @PostConstruct
    public void startIndexCreation() {
        var indexSpecification = MongoIndexSpecification.builder()
            .definition("{ randomBoolean: 1, randomLong: 1 }")
            .build();
        new Thread(() -> mongoIndexOperations.createIndex(indexSpecification)).start();
    }
}
```

The class `MongoIndexOperations` is a wrapper around `MongoClient`, but you could use `MongoTemplate` or `ReactiveMongoTemplate` too.
I used `MongoClient` because it's Spring independent, which would make it possible to use `MongoIndexOperations` in non-Spring applications too.
See [MongoIndexOperations.java](https://github.com/ljpengelen/mongo-index-experiments/blob/main/src/main/java/nl/cofx/mongo/indices/experiment/operations/MongoIndexOperations.java) for the complete implementation.

It could happen that some of the indexes you need are already present on some deployment environments,
for example because someone created them manually.
If you know the names of these indexes,
you can just issue create statements like the one above.
If the index already exists, nothing will happen, as discussed above.
If it doesn't exist, it will be created.

If the naming is not consistent across deployment environments,
things are a little trickier.
In such cases, you first have to determine whether a given index exists, regardless of the name, and only create it when it doesn't exist.

```java
@PostConstruct
public void startIndexCreation() {
    var indexSpecification = MongoIndexSpecification.builder()
        .definition("{ randomBoolean: 1, randomLong: 1 }")
        .build();
    new Thread(() -> {
        if (mongoIndexOperations.findIndex(indexSpecification) == null) {
            mongoIndexOperations.createIndex(indexSpecification.toBuilder()
                .name("name-that-does-not-exist-in-any-deployment-environment")
                .build());
        }
    }).start();
}
```

Ideally, you'd use some migration framework that ensures that each index is only created once,
instead of creating it (or at least verifying its existence) each time your app starts.
For SQL databases, [Flyway](https://flywaydb.org/) provides such functionality.
I have no experience with any open-source counterpart for MongoDB.

## Conclusion

If you have a few minutes to spare,
I advise you to clone <https://github.com/ljpengelen/mongo-index-experiments> and do some experiments yourself.
The proof of the pudding is in the eating.