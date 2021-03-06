# bud-paxos
Experimenting with implementing things in bud.

### Installation
Follow the installation guide [here](https://github.com/bloom-lang/bud/blob/master/docs/getstarted.md). That repository also contains docs on bud syntax, like this [useful cheatsheet](https://github.com/bloom-lang/bud/blob/master/docs/cheat.md).

### Running Paxos or Compartmentalized Paxos
The code should be run in this order: acceptors, proposers, then clients, each in a separate shell window. To change the number of acceptors, proposers, etc, modify the constants at the bottom of the `paxos_protocol.rb` file. Bloom modules that take in these numbers as parameters don't fare well with budplot; don't ask why. Therefore they're hardcoded.

Note: I have yet to test with more than 1 proposer or client. That's a big yikes.

##### Acceptor
```shell
ruby paxos_acceptor.rb <acceptor_id>
```
Replace `<acceptor_id>` with a number, starting from 1. The next acceptor should be 2, etc.

##### Proposer
```shell
ruby paxos_proposer.rb <proposer_id>
```
Replace `<proposer_id>` with a number, starting from 1. The next proposer should be 2, etc. Leader election should happen immediately; you will see some debug outputs.

##### Client
```shell
ruby paxos_client.rb <num_proposers>
```
Replace `<num_proposers>` with the number of proposers you spun up. You can input commands by typing in the terminal here, then hitting enter. You'll see them with a slot assigned if all goes well. Yay!

### Running 2PC
The code should be run in this order: coordinator, participants, then client, each in a separate shell window. Type input into the client to test.

## budplot
Generate a dataflow graph by running the following in their respective directories.

#### Paxos or Compartmentalized Paxos
```shell
budplot paxos_acceptor_module.rb paxos_client_module.rb paxos_proposer_module.rb paxos_protocol.rb PaxosAcceptorModule PaxosClientModule PaxosProposerModule PaxosProtocol
```

#### 2PC
```shell
budplot client_module.rb coordinator_module.rb participant_module.rb 2pc_protocol.rb ClientModule CoordinatorModule ParticipantModule TwoPcProtocol
```