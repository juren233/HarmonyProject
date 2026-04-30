import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';
import window from '@ohos.window';

export default class TestAbility extends UIAbility {
    onCreate(want, launchParam) {
        var abilityDelegator: any
        abilityDelegator = AbilityDelegatorRegistry.getAbilityDelegator()
        var abilityDelegatorArguments: any
        abilityDelegatorArguments = AbilityDelegatorRegistry.getArguments()
        Hypium.hypiumTest(abilityDelegator, abilityDelegatorArguments, testsuite)
    }

    onDestroy() {
    }

    onWindowStageCreate(windowStage: window.WindowStage) {
        windowStage.loadContent('testability/pages/Index', (err, data) => {
            if (err.code) {
                return;
            }
        });
    }

    onWindowStageDestroy() {
    }

    onForeground() {
    }

    onBackground() {
    }
}