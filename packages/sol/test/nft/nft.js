const { expect } = require("chai");
const { toUtf8Bytes } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

const URI = "Token Uri";
const NAME = "CCAsset token name";
const DESCRIPTION = "CCAsset name description";
const VALUE = BigInt(0.1 * 10 ** 18);

const MINTER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("MINTER_ROLE")
);
const LOCKER_ROLE = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes("LOCKER_ROLE")
);

const deployContract = async (contract, params) => {
  let c = await ethers.getContractFactory(contract);
  if (params) c = await c.deploy(...params);
  else c = await c.deploy();
  return await c.deployed();
};

const deployContracts = async () => {
  const nft = await deployContract("CCAssets", []);
  return { nft };
};

const _formatEther = (amount) => {
  return Number(ethers.utils.formatEther(amount));
};

describe("My Token / MTK", async () => {
  let deployer;
  let user;
  let nft;

  beforeEach(async () => {
    // get accounts
    [deployer, user] = await ethers.getSigners();

    // deploy token contract
    ({ nft } = await deployContracts());

    // grant LOCKER_ROLE of the nft
    await nft.grantRole(LOCKER_ROLE, deployer.address);
  });

  it("Should be mintable with RBAC", async () => {
    // check balance of deployer
    let balance = await nft.balanceOf(deployer.address);
    expect(balance).to.equal(0);

    /* the metadata is assumed to come from IPFS */
    // the uri, name, description, value will be stored offchain like IPFS
    let transaction = await nft.safeMint(
      deployer.address,
      URI,
      NAME,
      DESCRIPTION,
      VALUE
    );
    let tx = await transaction.wait();
    const tokenId = tx.events[0].args[2];

    // check the metadata on chain
    const metadata = await nft.getMetadataOnChain(tokenId);
    expect(metadata.name).to.equal(NAME);
    expect(metadata.description).to.equal(DESCRIPTION);
    expect(metadata.value).to.equal(VALUE);
    expect(await nft.tokenURI(tokenId)).to.equal(URI);

    // check minter balance
    balance = await nft.balanceOf(deployer.address);
    expect(balance).to.equal(1);

    // mint without permission
    try {
      await nft
        .connect(user)
        .safeMint(deployer.address, URI, NAME, DESCRIPTION, VALUE);
    } catch (error) {
      const revert = new RegExp(
        "AccessControl: account " +
          user.address.toLowerCase() +
          " is missing role " +
          MINTER_ROLE
      );
      expect(error.message).match(revert);
    }
  });

  it("Should be able to be locked", async () => {
    // mint nft
    let transaction = await nft.safeMint(
      deployer.address,
      URI,
      NAME,
      DESCRIPTION,
      VALUE
    );
    let tx = await transaction.wait();
    const tokenId = tx.events[0].args[2];

    // check the metadata on chain
    let metadata = await nft.getMetadataOnChain(tokenId);

    // get blocktimestamp
    expect(metadata.name).to.equal(NAME);
    expect(metadata.description).to.equal(DESCRIPTION);
    expect(metadata.value).to.equal(VALUE);
    expect(metadata.isLocked).to.equal(false);
    expect(await nft.tokenURI(tokenId)).to.equal(URI);

    // lock nft
    await nft.handleLock(tokenId, true);

    // check the locked state
    expect(await nft.verifyLockedState(tokenId)).to.equal(true);

    // only the token owner can lock nft
    try {
      await nft.connect(user).handleLock(tokenId, true);
    } catch (error) {
      const revert = new RegExp(
        "AccessControl: account " +
          user.address.toLowerCase() +
          " is missing role " +
          LOCKER_ROLE
      );
      expect(error.message).match(revert);
    }
    // console.log(Object.keys(nft)); // get all contract methods

    // token transfer should be failed
    try {
      await nft["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        user.address,
        tokenId
      ); // overroaded function call
    } catch (error) {
      expect(error.message).match(/Denied: Locked token/);
    }

    // unlock nft
    await nft.handleLock(tokenId, false);

    // check the locked state
    expect(await nft.verifyLockedState(tokenId)).to.equal(false);

    await nft["safeTransferFrom(address,address,uint256)"](
      deployer.address,
      user.address,
      tokenId
    );
    expect(await nft.ownerOf(tokenId)).to.equal(user.address);
  });

  it("Should be able to update metadata onchain", async () => {
    // mint nft
    let transaction = await nft.safeMint(
      deployer.address,
      URI,
      NAME,
      DESCRIPTION,
      VALUE
    );
    let tx = await transaction.wait();
    const tokenId = tx.events[0].args[2];

    // check the metadata on chain
    let metadata = await nft.getMetadataOnChain(tokenId);
    expect(metadata.name).to.equal(NAME);
    expect(metadata.description).to.equal(DESCRIPTION);
    expect(metadata.value).to.equal(VALUE);
    expect(metadata.isLocked).to.equal(false);
    expect(await nft.tokenURI(tokenId)).to.equal(URI);

    await nft.setMetadataOnChain(
      tokenId,
      "Updated name",
      BigInt(0.2 * 10 ** 18),
      true
    );

    // check updated metadata
    metadata = await nft.getMetadataOnChain(tokenId);
    expect(metadata.name).to.equal("Updated name");
    expect(_formatEther(metadata.value)).to.equal(0.2);
    expect(metadata.isLocked).to.equal(true);
  });

  it("Should be able to update tokenUri", async () => {
    // mint nft
    let transaction = await nft.safeMint(
      deployer.address,
      URI,
      NAME,
      DESCRIPTION,
      VALUE
    );
    let tx = await transaction.wait();
    const tokenId = tx.events[0].args[2];

    // check token uri
    expect(await nft.tokenURI(tokenId)).to.equal(URI);

    // update token Uri
    await nft.setTokenURI(tokenId, "Updated Uri");

    // check updated uri
    expect(await nft.tokenURI(tokenId)).to.equal("Updated Uri");
  });
});
