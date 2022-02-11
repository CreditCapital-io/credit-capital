<template>
  <div class="home stack-page">
    <div class="swap-container">
      <div class="panel-container inner-container">
        <div class="panel stake-panel">
          <h1 class="panel-title">Stake</h1>
          <div class="panel-content stake-panel-content">
            <input
              type="number"
              placeholder="0.00"
              class="input-custom"
              v-model="stakeAmount"
              @input="onChangeStakeAmount()"
            />
            <button type="submit" class="btn-custom" @click="stake">
              {{ stakeButtonString }}
            </button>
          </div>
        </div>
        <div class="panel stake-panel">
          <h1 class="panel-title">Unstake</h1>
          <div class="panel-content stake-panel-content">
            <input
              type="number"
              placeholder="0.00"
              class="input-custom"
              v-model="unstakeAmount"
              @input="onChangeUnstakeAmount()"
            />
            <button type="submit" class="btn-custom" @click="unstake">
              {{ unstakeButtonString }}
            </button>
          </div>
        </div>
      </div>
      <DappFooter />
    </div>
  </div>
</template>

<script lang="ts" setup>
// @ts-ignore
import DappFooter from "@/components/DappFooter.vue";
import { computed, watchEffect, ref } from "vue";
// @ts-ignore
import { format } from "@/utils";
// @ts-ignore
import { useStore } from "@/store";
// @ts-ignore
import { checkConnection, checkBalance } from "@/utils/notifications";

const store = useStore();
const formatedUserPosition = ref(0);
const stakeAmount = ref(0);
const unstakeAmount = ref(0);
let stakeButtonString = ref("Enter");
let unstakeButtonString = ref("Enter");

//const connected = computed(() => store.getters["accounts/isUserConnected"]);
const wallet = computed(() => store.getters["accounts/getActiveAccount"]);
const contract = computed(() => store.getters["contracts/getRewardsContract"]);

const stake = async () => {
  if (checkConnection(store) && checkBalance(stakeAmount.value)) {
    if (stakeButtonString.value === 'Approve') {
      await store.dispatch("tokens/approve", {
        contract: contract.value,
        amount: parseFloat(stakeAmount.value as string),
        address: wallet.value,
      });
      stakeButtonString.value = "Enter";
    } else {
      const allowance = await store.dispatch("tokens/checkAllowance", {
        contract: contract.value,
        amount: parseFloat(stakeAmount.value as string),
        address: wallet.value,
      });

      if (allowance) {
        store.dispatch("rewards/stake", { amount: stakeAmount.value });
      } else {
        stakeButtonString.value = "Approve";
      }
    }
  }
};

const unstake = async () => {
  // check connection
  if (checkConnection(store) && checkBalance(unstakeAmount.value)) {
    if (unstakeButtonString.value === 'Approve') {
      await store.dispatch("tokens/approve", {
        contract: contract.value,
        amount: parseFloat(unstakeAmount.value as string),
        address: wallet.value,
      });
      unstakeButtonString.value = "Enter";
    } else {
      const allowance = await store.dispatch("tokens/checkAllowance", {
        contract: contract.value,
        amount: parseFloat(unstakeAmount.value as string),
        address: wallet.value,
      });

      if (allowance) {
        store.dispatch("rewards/unstake", { amount: unstakeAmount.value });
      } else {
        unstakeButtonString.value = "Approve";
      }
    }
  }
};
const userPosition = computed(() => store.getters["rewards/getUserPosition"]);

const onChangeStakeAmount = () => {
  stakeButtonString.value = "Enter";
}

const onChangeUnstakeAmount = () => {
  unstakeButtonString.value = "Enter";
}

watchEffect(() => {
  if (userPosition.value) {
    formatedUserPosition.value = format(userPosition.value);
  }
});
</script>

<style>
.stake-panel {
  margin: 0 12%;
}

.stake-panel-content {
  height: 40vh;
  padding: 10px 40px;
}
</style>
