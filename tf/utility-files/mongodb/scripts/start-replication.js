
const replStatus = rs.status();

if (replStatus && replStatus.ok === 1) {
  print('### Replication OK ###');
  printjson(replStatus);
} else {
  print('### Starting replication... ###');
  const cfg = {
    _id: 'rs0',
    version: 1,
    members: [
      {
        _id: 0,
        host: 'mem-mongodb-0.mem-mongodb.memories.svc.cluster.local:27017',
        priority: 2
      },
      {
        _id: 1,
        host: 'mem-mongodb-1.mem-mongodb.memories.svc.cluster.local:27017',
        priority: 1
      },
      {
        _id: 2,
        host: 'mem-mongodb-2.mem-mongodb.memories.svc.cluster.local:27017',
        priority: 1
      }
    ]
  };
  printjson(cfg);
  const replInitiate = rs.initiate(cfg);
  print('### Replica Set initiate ###');
  printjson(replInitiate);
  print('### Replica Set status ###');
  printjson(rs.status());
}
