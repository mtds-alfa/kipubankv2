import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Conta de deploy:", deployer.address);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Saldo:", ethers.formatEther(balance), "ETH");
  
  // Verificar se há fundos suficientes (0.01 ETH é um valor seguro para deploy)
  if (balance < ethers.parseEther("0.01")) {
    console.log("\n⚠️  ATENÇÃO: Saldo insuficiente para realizar o deploy.");
    console.log("Por favor, envie ETH para esta conta:");
    console.log(`Endereço: ${deployer.address}`);
    console.log("\nVocê pode obter ETH de teste para a rede Sepolia em:");
    console.log("- https://sepoliafaucet.com/");
    console.log("- https://www.infura.io/faucet/sepolia");
  } else {
    console.log("\n✅ Saldo suficiente para realizar o deploy.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});