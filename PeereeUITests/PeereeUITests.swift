//
//  PeereeUITests.swift
//  PeereeUITests
//
//  Created by Christopher Kobusch on 30.10.16.
//  Copyright © 2016 Kobusch. All rights reserved.
//

import XCTest

class PeereeUITests: XCTestCase {
        
    override func setUp() {
        super.setUp()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        XCUIApplication().launch()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testOnboarding() {
        
        let app = XCUIApplication()
        app.children(matching: .window).element(boundBy: 0).children(matching: .other).element.swipeLeft()
        app.buttons["What do you want with my data?"].tap()
        
        let app2 = app
        app2.tables.staticTexts["Decentralized Information"].tap()
        
        let tablesQuery = app.tables
        tablesQuery.cells.containing(.staticText, identifier:"Decentralized Information").children(matching: .textView).element.swipeUp()
        tablesQuery.cells.containing(.staticText, identifier:"Temporary").children(matching: .textView).element.swipeUp()
        app.buttons["Sounds great!"].tap()
        app.buttons["PortraitPlaceholder"].tap()
        app.sheets.buttons["Omit Portrait"].tap()
        
        let nameTextField = app.textFields["Name"]
        nameTextField.tap()
        nameTextField.typeText("Name")
        app.pageIndicators["page 2 of 2"].tap()
        app.typeText("\n")
        app2.buttons["Female"].tap()
        app.buttons["Get started >"].tap()
        
    }
    
}
