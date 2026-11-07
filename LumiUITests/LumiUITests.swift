import XCTest

@MainActor final class LumiUITests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if element.isHittable { return }
        if !element.exists { for _ in 0..<4 { app.swipeDown(velocity: .fast) } }
        for _ in 0..<12 {
            if element.isHittable { return }
            if element.exists && element.frame.minY < 100 { app.swipeDown() }
            else { app.swipeUp() }
        }
    }
    private func tapSettings(_ identifier: String, in app: XCUIApplication) {
        let element = app.buttons[identifier]
        reveal(element, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 3)); XCTAssertTrue(element.isHittable); element.tap()
    }
    func testProviderTemplatesChatGPTClaudeAndCustom() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsReady"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap(); app.buttons["profile.settings"].tap()
        tapSettings("settings.provider", in: app)
        let template = app.buttons["provider.template"]
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        for (name, url, model) in [
            ("ChatGPT", "https://api.openai.com/v1", "gpt-6-luna"),
            ("Claude", "https://api.anthropic.com/v1", "claude-sonnet-5-5"),
            ("DeepSeek", "https://api.deepseek.com", "deepseek-flash")
        ] {
            template.tap()
            XCTAssertFalse(app.buttons["OpenRouter"].exists)
            let option = app.buttons[name]; XCTAssertTrue(option.waitForExistence(timeout: 3)); option.tap()
            XCTAssertEqual(app.textFields["provider.baseURL"].value as? String, url)
            XCTAssertEqual(app.textFields["provider.model"].value as? String, model)
        }
        template.tap(); app.buttons["自定义"].tap()
        XCTAssertEqual(app.textFields["provider.baseURL"].value as? String, "Base URL")
        XCTAssertEqual(app.textFields["provider.model"].value as? String, "模型名称")
    }

    func testFirstEntryProfileSetupAndLaterEditing() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsProfileSetup"]; app.launch()
        XCTAssertTrue(app.buttons["onboarding.privacy"].waitForExistence(timeout: 10))
        app.buttons["onboarding.privacy"].tap()
        let name = app.textFields["profile.name"]; let save = app.buttons["profile.save"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile.cancel"].exists)
        XCTAssertFalse(save.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "首次个人资料卡"; attachment.lifetime = .keepAlways; add(attachment)
        name.tap(); name.typeText("Mina\n"); save.tap()
        XCTAssertTrue(app.buttons["provider.skip"].waitForExistence(timeout: 5))
        app.buttons["provider.skip"].tap()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["profile.edit"].label.contains("Mina"))
        app.buttons["profile.edit"].tap()
        XCTAssertEqual(name.value as? String, "Mina")
        XCTAssertTrue(app.buttons["profile.cancel"].exists)
        XCTAssertFalse(app.buttons["profile.birthday.clear"].exists)
    }

    func testOnlyDaughterRemainsInChatsAndContacts() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsReady"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 10))
        let conversations = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation.'"))
        XCTAssertEqual(conversations.count, 1)
        for name in ["小夏", "林序", "阿澈", "望舒"] { XCTAssertFalse(app.buttons["conversation.\(name)"].exists) }
        app.tabBars.buttons["列表"].tap()
        XCTAssertTrue(app.buttons["character.select.大肥鱼"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'character.select.'")).count, 1)
        XCTAssertEqual(app.staticTexts["characters.count"].label, "1 位好友")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Only 大肥鱼 remains"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPersonalProfileEditingAndChatWithoutIntro() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsReady"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 10))
        app.buttons["conversation.大肥鱼"].tap()
        XCTAssertTrue(app.buttons["chat.settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["慢慢说，我在听。"].exists)
        XCTAssertFalse(app.staticTexts["大肥鱼 是 AI 好友 · 对话保存在本机"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["我的"].tap(); app.buttons["profile.edit"].tap()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Mina\n")
        app.buttons["profile.birthday"].tap()
        XCTAssertTrue(app.datePickers["profile.birthday.picker"].waitForExistence(timeout: 3))
        app.buttons["profile.birthday"].tap()
        let zodiac = app.buttons["profile.zodiac"]
        reveal(zodiac, in: app); zodiac.tap()
        app.buttons["狮子座"].tap()
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile.edit"].label.contains("Mina"))
        let savedZodiac = app.descendants(matching: .any).matching(identifier: "profile.summary.zodiac").firstMatch
        XCTAssertTrue(savedZodiac.label.contains("狮子座") || (savedZodiac.value as? String)?.contains("狮子座") == true)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Personal profile saved"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["profile.edit"].tap()
        XCTAssertEqual(name.value as? String, "Mina")
        name.tap(); name.typeText("Changed\n")
        app.buttons["profile.cancel"].tap()
        app.buttons["profile.edit"].tap()
        XCTAssertEqual(name.value as? String, "Mina")
        let clearBirthday = app.buttons["profile.birthday.clear"]
        reveal(clearBirthday, in: app); clearBirthday.tap()
        app.buttons["profile.save"].tap()
        XCTAssertFalse(app.staticTexts["生日"].exists)
        XCTAssertTrue(savedZodiac.label.contains("狮子座") || (savedZodiac.value as? String)?.contains("狮子座") == true)
    }
    func testInteractionScrollResumeAndSettings() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady", "-lumiUITestsHistory"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        app.buttons["conversation.小夏"].tap()
        XCTAssertFalse(app.buttons["chat.latest"].exists)
        app.scrollViews.firstMatch.swipeDown()
        let latest = app.buttons["chat.latest"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        latest.tap()
        XCTAssertFalse(latest.exists)
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        for _ in 0..<5 { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertFalse(latest.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["我的"].tap()
        app.buttons["profile.settings"].tap()
        tapSettings("settings.interaction", in: app)
        XCTAssertTrue(app.switches["interaction.animations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["interaction.haptics"].exists)
        let animationSwitch = app.switches["interaction.animations"]
        let original = animationSwitch.value as? String
        animationSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let changed = NSPredicate(format: "value == %@", original == "1" ? "0" : "1")
        expectation(for: changed, evaluatedWith: animationSwitch)
        waitForExpectations(timeout: 3)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Motion and haptics"; screenshot.lifetime = .keepAlways; add(screenshot)
        animationSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
    func testStage8BackupVoiceAndShareEntries() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        app.buttons["conversation.小夏"].tap()
        app.buttons["chat.share"].tap()
        XCTAssertTrue(app.navigationBars["分享对话"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["share.card"].exists)
        app.buttons["完成"].tap()
        app.buttons["chat.attach"].tap(); app.buttons["语音输入"].tap()
        let microphone = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS 'Allow' OR label CONTAINS '允许'" )).firstMatch
        if microphone.waitForExistence(timeout: 3) { microphone.tap() }
        if microphone.waitForExistence(timeout: 3) { microphone.tap() }
        XCTAssertTrue(app.buttons["chat.holdToTalk"].waitForExistence(timeout: 5) || app.buttons["启用麦克风"].exists)
        XCTAssertTrue(app.buttons["切换文字输入"].exists)
        if app.buttons["chat.holdToTalk"].exists {
            app.buttons["chat.holdToTalk"].press(forDuration: 1.5)
            if app.buttons["播放语音"].waitForExistence(timeout: 8) {
                app.buttons["播放语音"].tap()
                XCTAssertFalse(app.staticTexts["语音播放失败，请重试。"].exists)
            } else {
                // This simulator host may expose no microphone. Verify the explicit fallback.
                XCTAssertTrue(app.staticTexts["当前没有可用的录音设备，请检查麦克风后重试。"].exists)
            }
        }
        app.buttons["切换文字输入"].tap()
        XCTAssertTrue(app.textFields["chat.input"].exists || app.textViews["chat.input"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["我的"].tap(); app.buttons["profile.settings"].tap()
        tapSettings("settings.backup", in: app)
        app.buttons["backup.export"].tap()
        XCTAssertTrue(app.buttons["backup.share"].waitForExistence(timeout: 20))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Stage 8 full backup ready"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testMarketThemeReviewInstallAndUninstall() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        app.buttons["profile.settings"].tap()
        app.buttons["settings.market"].tap()
        XCTAssertTrue(app.staticTexts["内置离线目录"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap(); search.typeText("暮色\n")
        XCTAssertFalse(app.buttons["market.item.lumi.friend.xinghe"].exists)
        let theme = app.buttons["market.item.lumi.theme.iris"]
        if !theme.isHittable { app.swipeUp() }
        XCTAssertTrue(theme.waitForExistence(timeout: 5)); theme.tap()
        app.buttons["market.preview"].tap()
        XCTAssertTrue(app.buttons["market.confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["聊天预览"].exists)
        app.buttons["market.confirm"].tap()
        XCTAssertTrue(app.buttons["market.preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["market.preview"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let installed = app.buttons["market.installed"]
        if !installed.isHittable { app.swipeDown() }
        XCTAssertTrue(installed.waitForExistence(timeout: 3)); installed.tap()
        let remove = app.buttons["market.uninstall.lumi.theme.iris"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3)); remove.tap()
        app.buttons["确认卸载"].tap()
        XCTAssertTrue(app.staticTexts["还没有安装市场内容"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Market uninstall completed"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testTokenUsageEntryRankingAndMilestones() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        XCTAssertFalse(app.buttons["settings.tokens"].exists)
        app.buttons["profile.settings"].tap()
        let entry = app.buttons["settings.tokens"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3)); entry.tap()
        XCTAssertTrue(app.staticTexts["tokens.total"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tokens.total"].label, "0")
        reveal(app.staticTexts["好友消耗排行"], in: app)
        XCTAssertTrue(app.staticTexts["好友消耗排行"].exists)
        let friend = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tokens.friend.'")).firstMatch
        if !friend.isHittable { app.swipeUp() }
        XCTAssertTrue(friend.waitForExistence(timeout: 3)); friend.tap()
        for title in ["1 亿 Token", "10 亿 Token", "30 亿 Token", "60 亿 Token", "100 亿 Token"] {
            let label = app.staticTexts[title].firstMatch
            if !label.isHittable { app.swipeUp() }
            XCTAssertTrue(label.waitForExistence(timeout: 3))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Lumi token milestones"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSettingsOnlyEntriesAndGroupCreation() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        for title in ["API 配置", "界面颜色", "技能管理", "工具授权"] { XCTAssertFalse(app.buttons[title].exists) }
        XCTAssertTrue(app.buttons["profile.settings"].exists)
        app.buttons["profile.settings"].tap()
        for entry in ["settings.provider", "settings.skills", "settings.tools", "settings.colors"] {
            let button = app.buttons[entry]
            if !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.tabBars.buttons["聊天"].tap()
        app.buttons["home.group"].tap()
        XCTAssertTrue(app.textFields["group.name"].waitForExistence(timeout: 5))
        for name in ["小夏", "林序", "阿澈", "望舒"] {
            let member = app.switches["group.member.\(name)"]
            if !member.isHittable { app.swipeUp() }
            XCTAssertTrue(member.waitForExistence(timeout: 3))
            member.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        if !app.textFields["group.name"].isHittable { app.swipeDown() }
        app.textFields["group.name"].tap(); app.textFields["group.name"].typeText("夜聊小分队")
        app.buttons["group.save"].tap()
        XCTAssertTrue(app.buttons["group.settings"].waitForExistence(timeout: 5))
        app.buttons["group.mentions"].tap()
        app.buttons["group.mention.小夏"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "group.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 3)); XCTAssertTrue((input.value as? String)?.contains("@小夏") == true)
        input.typeText(" 今天过得怎么样")
        app.buttons["group.send"].tap()
        XCTAssertTrue(app.staticTexts["@小夏  今天过得怎么样"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["group.error"].exists || app.buttons["重试"].waitForExistence(timeout: 5))
        app.buttons["group.settings"].tap()
        let automatic = app.switches["group.automatic"]
        if !automatic.isHittable { app.swipeUp() }
        if !automatic.isHittable { app.swipeUp() }
        XCTAssertEqual(automatic.value as? String, "0")
        let sharing = app.switches["group.memory"]
        if !sharing.isHittable { app.swipeDown() }
        XCTAssertEqual(sharing.value as? String, "0")
        app.buttons["取消"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Lumi group chat"; attachment.lifetime = .keepAlways; add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["group.conversation.夜聊小分队"].waitForExistence(timeout: 5))
        app.buttons["group.conversation.夜聊小分队"].tap()
        app.buttons["group.settings"].tap()
        for _ in 0..<8 {
            if app.buttons["group.delete"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["group.delete"].tap()
        XCTAssertTrue(app.alerts["删除这个群及其全部群消息？"].waitForExistence(timeout: 3))
        app.alerts.buttons["取消"].tap()
        app.buttons["group.delete"].tap()
        app.alerts.buttons["删除群聊"].tap()
        XCTAssertTrue(app.buttons["home.group"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group.conversation.夜聊小分队"].exists)
        XCTAssertTrue(app.buttons["conversation.小夏"].exists)
    }

    func testReturningFromBackgroundDoesNotReplaySplash() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.descendants(matching: .any)["launch.splash"].exists)
        XCTAssertTrue(app.buttons["conversation.小夏"].exists)
    }

    func testDefaultProviderColorsPinsAndSkills() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        let chat = app.buttons["conversation.小夏"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.press(forDuration: 1)
        let pin = app.buttons["置顶聊天"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3)); pin.tap()
        XCTAssertTrue(app.images["已置顶"].exists || app.staticTexts["已置顶"].exists)
        chat.press(forDuration: 1)
        XCTAssertTrue(app.buttons["取消置顶"].waitForExistence(timeout: 3)); app.buttons["取消置顶"].tap()
        app.tabBars.buttons["我的"].tap()
        app.buttons["profile.settings"].tap()
        app.buttons["settings.provider"].tap()
        XCTAssertTrue(app.textFields["provider.model"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["provider.model"].value as? String, "deepseek-flash")
        XCTAssertEqual(app.switches["provider.tools"].value as? String, "1")
        XCTAssertEqual(app.switches["provider.vision"].value as? String, "1")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.colors"].tap()
        let purple = app.buttons["theme.purple"]
        if !purple.isHittable { app.swipeUp() }
        XCTAssertTrue(purple.waitForExistence(timeout: 5)); purple.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Custom Lumi colors"; attachment.lifetime = .keepAlways; add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.skills"].tap()
        XCTAssertTrue(app.switches["skill.enabled.英语陪练"].waitForExistence(timeout: 5))
        let enabled = app.switches["skill.enabled.英语陪练"]
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: enabled)], timeout: 3) == .completed)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["聊天"].tap()
        app.buttons["conversation.小夏"].tap()
        app.buttons["chat.attach"].tap()
        app.buttons["chat.skills"].tap()
        XCTAssertTrue(app.navigationBars["挂载技能"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skill.mount.英语陪练"].exists)
        app.buttons["skill.mount.哄睡"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "哄睡").firstMatch.waitForExistence(timeout: 3))
    }

    func testMemePickerOfflineSendAndLibraryEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        app.buttons["conversation.小夏"].tap()
        app.buttons["chat.memes"].tap()
        let happy = app.buttons["meme.pick.开心"]
        XCTAssertTrue(happy.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Meme picker"; attachment.lifetime = .keepAlways; add(attachment)
        happy.tap()
        XCTAssertTrue(app.staticTexts["表情已保存在聊天中。配置 API 后，可让好友回复。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["provider.baseURL"].exists)
        let sent = app.buttons["meme.message.开心"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5)); sent.tap()
        XCTAssertTrue(app.navigationBars["表情预览"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["我的"].tap()
        app.buttons["profile.memes"].tap()
        XCTAssertTrue(app.navigationBars["表情图库"].waitForExistence(timeout: 5))
        app.buttons["AI 表情设置"].tap()
        let enabled = app.switches["memes.aiEnabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(NSPredicate(format: "value == '0'").evaluate(with: enabled) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: enabled)], timeout: 3) == .completed)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.containing(.staticText, identifier: "Lumi 小星星").firstMatch.tap()
        let packSwitch = app.switches["启用此图库"]
        XCTAssertTrue(packSwitch.waitForExistence(timeout: 5))
        packSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: packSwitch)], timeout: 3) == .completed)
        let firstImage = app.buttons["meme.edit.加油"]
        for _ in 0..<4 { if firstImage.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(firstImage.waitForExistence(timeout: 5)); XCTAssertTrue(firstImage.isHittable); firstImage.tap()
        XCTAssertTrue(app.navigationBars["编辑表情"].waitForExistence(timeout: 5))
        let caption = app.descendants(matching: .any).matching(identifier: "memes.caption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5)); caption.tap()
        caption.typeText("呀")
        let updated = caption.value as? String ?? ""
        XCTAssertTrue(updated.contains("呀"))
        app.buttons["memes.save"].tap()
        XCTAssertTrue(app.staticTexts[updated].waitForExistence(timeout: 5))
    }

    func testMomentsPersonalTagsSaveCancelClearAndFriendScope() {
        let app = XCUIApplication(); app.launchArguments = ["-lumiUITests", "-lumiUITestsReady"]; app.launch()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 10))
        app.tabBars.buttons["朋友圈"].tap()
        let edit = app.buttons["moments.tags.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let input = app.descendants(matching: .any).matching(identifier: "moments.tags.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("爱拍照也爱到处走走看看，喜欢猫也喜欢安静生活，慢热但是熟悉以后话多")
        app.buttons["moments.tags.save"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); XCTAssertEqual(edit.value as? String, "爱拍照也爱到处走走看看，喜欢猫也喜欢安静生活，慢热但是熟悉以后话多")
        let cover = XCTAttachment(screenshot: app.screenshot()); cover.name = "朋友圈个性化标签"; cover.lifetime = .keepAlways; add(cover)
        app.buttons["moments.friend.大肥鱼"].tap()
        XCTAssertTrue(app.navigationBars["大肥鱼的朋友圈"].waitForExistence(timeout: 5))
        XCTAssertFalse(edit.exists); XCTAssertFalse(app.staticTexts["爱拍照也爱到处走走看看"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["moments.settings"].tap(); app.buttons["moments.tags.settings"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, "爱拍照也爱到处走走看看，喜欢猫也喜欢安静生活，慢热但是熟悉以后话多")
        let editor = XCTAttachment(screenshot: app.screenshot()); editor.name = "标签编辑预览"; editor.lifetime = .keepAlways; add(editor)
        app.buttons["moments.tags.clear"].tap(); app.buttons["moments.tags.cancel"].tap()
        app.buttons["moments.tags.settings"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, "爱拍照也爱到处走走看看，喜欢猫也喜欢安静生活，慢热但是熟悉以后话多")
        app.buttons["moments.tags.clear"].tap(); input.tap(); input.typeText("one,two,three,four")
        XCTAssertFalse(app.buttons["moments.tags.save"].isEnabled)
        app.buttons["moments.tags.clear"].tap(); app.buttons["moments.tags.save"].tap()
        XCTAssertTrue(app.buttons["moments.tags.settings"].waitForExistence(timeout: 5)); app.buttons["完成"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); XCTAssertEqual(edit.value as? String, "")
    }

    func testMomentsFriendFeedLikesCommentsAndCoverSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady", "-lumiUITestsMoments"]
        app.launch()
        XCTAssertTrue(app.buttons["conversation.大肥鱼"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells.element(boundBy: 0).buttons["conversation.大肥鱼"].exists)
        app.tabBars.buttons["朋友圈"].tap()
        XCTAssertTrue(app.buttons["moments.cover.change"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["moments.cover.custom"].waitForExistence(timeout: 3))
        let profile = app.buttons["moments.friend.大肥鱼"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5)); profile.tap()
        XCTAssertTrue(app.navigationBars["大肥鱼的朋友圈"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["摸鱼回来了"].exists)
        let like = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moments.like.'")).firstMatch
        reveal(like, in: app); like.tap()
        XCTAssertEqual(like.label, "取消点赞")
        app.buttons["评论"].tap()
        let comment = app.textFields["moments.comment.text"]
        XCTAssertTrue(comment.waitForExistence(timeout: 3)); comment.tap(); comment.typeText("今天也要开心")
        app.buttons["moments.comment.send"].tap()
        XCTAssertTrue(app.buttons["我：今天也要开心，点击回复"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["moments.settings"].tap()
        let automatic = app.switches["moments.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(automatic.value as? String, "0")
        let reset = app.buttons["恢复默认背景"]
        reveal(reset, in: app); XCTAssertTrue(reset.isEnabled); reset.tap(); XCTAssertFalse(reset.isEnabled)
        app.buttons["完成"].tap()
        XCTAssertFalse(app.images["moments.cover.custom"].exists)
        app.buttons["moments.cover.change"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == '取消'" )).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["moments.cover.change"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Friend Moments"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testFourTabsFriendGenerationAttachmentsAndMoments() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 10))
        for title in ["聊天", "列表", "朋友圈", "我的"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
        XCTAssertFalse(app.textFields["chat.input"].exists)
        app.buttons["home.add"].tap()
        app.buttons["friends.generate"].tap()
        XCTAssertTrue(app.textFields["friend.generate.name"].waitForExistence(timeout: 5))
        app.buttons["friend.generate.submit"].tap()
        XCTAssertTrue(app.staticTexts["friend.generate.error"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["从聊天记录生成"].tap()
        XCTAssertTrue(app.buttons["friend.history.import"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["取消"].tap()
        app.buttons["conversation.小夏"].tap()
        app.buttons["chat.attach"].tap()
        XCTAssertTrue(app.buttons["图片"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["文件"].exists)
        app.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["朋友圈"].tap()
        app.buttons["moments.compose"].tap()
        let text = app.textFields["moments.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("今天遇见一点光")
        app.buttons["moments.publish"].tap()
        XCTAssertTrue(app.staticTexts["今天遇见一点光"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertFalse(app.buttons["API 配置"].exists)
        XCTAssertTrue(app.buttons["profile.settings"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Lumi four tabs"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSkipAPIKeepsDraftAndContextDefaultsOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.privacy"].waitForExistence(timeout: 10))
        app.buttons["onboarding.privacy"].tap()
        XCTAssertTrue(app.buttons["provider.skip"].waitForExistence(timeout: 5))
        app.buttons["provider.skip"].tap()
        XCTAssertTrue(app.buttons["conversation.小夏"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["chat.input"].exists)
        app.buttons["conversation.小夏"].tap()
        let input = app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("稍后再连接")
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.textFields["provider.baseURL"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertEqual(input.value as? String, "稍后再连接")
        app.buttons["chat.settings"].tap()
        app.buttons["settings.proactive"].tap()
        let proactive = app.switches["proactive.enabled"]
        XCTAssertTrue(proactive.waitForExistence(timeout: 5)); XCTAssertEqual(proactive.value as? String, "0")
        app.swipeUp()
        for identifier in ["context.weather", "context.calendar", "context.battery"] {
            let control = app.switches[identifier]
            if !control.isHittable { app.swipeUp() }
            XCTAssertTrue(control.exists); XCTAssertEqual(control.value as? String, "0")
        }
        app.swipeUp()
        app.buttons["proactive.guide"].tap()
        XCTAssertTrue(app.staticTexts["让问候融入日常"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Stage 3 automation guide"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSplashReplacesAgeGateAndProviderValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends"]
        app.launch()
        XCTAssertFalse(app.switches["onboarding.adult"].exists)
        let privacy = app.buttons["onboarding.privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["launch.splash"].exists)
        privacy.tap()
        let base = app.textFields["provider.baseURL"]
        XCTAssertTrue(base.waitForExistence(timeout: 5))
        base.tap()
        if let current = base.value as? String { base.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
        base.typeText("http://invalid.example")
        app.swipeUp()
        app.buttons["provider.save"].tap()
        XCTAssertTrue(app.staticTexts["provider.notice"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "API configuration validation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testCharacterCreationMemoryIsolationAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["-lumiUITests", "-lumiUITestsSampleFriends", "-lumiUITestsReady"]
        app.launch()
        let list = app.tabBars.buttons["列表"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        list.tap()
        app.buttons["characters.create"].tap()
        app.buttons["friends.custom"].tap()
        let name = app.textFields["character.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("测试角色")
        let persona = app.descendants(matching: .any).matching(identifier: "character.persona").firstMatch
        persona.tap(); persona.typeText("温柔、简短，认真听用户说话。")
        app.buttons["character.save"].tap()
        XCTAssertTrue(app.buttons["chat.memories"].waitForExistence(timeout: 5))
        app.buttons["chat.memories"].tap()
        let addMemory = app.buttons["memory.add"]
        for _ in 0..<5 {
            if addMemory.exists && addMemory.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(addMemory.waitForExistence(timeout: 3)); XCTAssertTrue(addMemory.isHittable)
        addMemory.tap()
        let fact = app.descendants(matching: .any).matching(identifier: "memory.text").firstMatch
        XCTAssertTrue(fact.waitForExistence(timeout: 5)); fact.tap(); fact.typeText("喜欢茉莉花茶")
        app.buttons["memory.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "memory.fact.喜欢茉莉花茶").firstMatch.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["列表"].tap()
        let other = app.buttons["character.select.林序"]
        if !other.isHittable { app.swipeUp() }
        XCTAssertTrue(other.waitForExistence(timeout: 5)); other.tap()
        app.buttons["chat.memories"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "memory.fact.喜欢茉莉花茶").firstMatch.exists)
        app.buttons["完成"].tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["chat.memories"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.switches["onboarding.adult"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Stage 2 character chat"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
