
import UIKit

//
//  Localization.swift
//
//  Created by Sasha Klovak on 25.11.2020.
//

import UIKit
import SwiftUI

enum Localization: String {
    case localization1 = "localization1.key"
    case localization2 = "localization2.key"
    case localization3 = "localization3.key"
}

extension Localization {
    
    private static let LanguageSettingsKey = "LanguageSettings"
    
    ///Localized string for selected enum case
    var value: String {
        let selectedLanguage = Localization.currentLanguage().localizationFileName
        guard let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj") else { return NSLocalizedString(rawValue, comment: "") }
        guard let bundle = Bundle(path: path) else { return NSLocalizedString(rawValue, comment: "") }
        return bundle.localizedString(forKey: rawValue, value: "", table: nil)
    }

    ///Pluralized string for Int value. Stirng example: "Some string %u other string"
    /// - Parameters:
    ///   - doubleNumber: Double value
    /// - Returns: 
    func pluralDoubleValue(with doubleNumber: Double) -> String {
        let selectedLanguage = Localization.currentLanguage().localizationFileName
        guard let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj") else { return NSLocalizedString(rawValue, comment: "") }
        guard let bundle = Bundle(path: path) else { return NSLocalizedString(rawValue, comment: "") }
        var localizationKey = ""

        let dividingBy10 = doubleNumber.truncatingRemainder(dividingBy: 10.0)
        let dividingBy100 = doubleNumber.truncatingRemainder(dividingBy: 100.0)
        if doubleNumber == 0.0 {
            localizationKey = rawValue + ".many"
        } else if doubleNumber > 0.0 && doubleNumber < 1.0 {
            localizationKey = rawValue + ".other"
        } else if dividingBy10 == 1.0 && dividingBy100 != 11.0 {
            localizationKey = rawValue + ".one"
        } else if (dividingBy10 > 1.0 && dividingBy10 < 5.0) && !(dividingBy100 > 11.0 && dividingBy100 < 15.0) {
            localizationKey = rawValue + ".other"
        } else if dividingBy10 == 0.0 || (dividingBy10 >= 5.0 && dividingBy10 < 10.0) || (dividingBy100 >= 11.0 && dividingBy100 < 15.0) {
            localizationKey = rawValue + ".many"
        }
        
        let formatString = bundle.localizedString(forKey: localizationKey, value: "", table: nil)
        let countString = String.formattedDoubleString(from: doubleNumber)
        return String(format: formatString, countString)
    }
    
    ///Pluralized string for Int value. Stirng example: "Some string %ld other string"
    /// - Parameters:
    ///   - intNumber: Int value
    /// - Returns: a string with an Int value in the correct format (singular/plural)
    func pluralIntValue(with intNumber: Int) -> String {
        let selectedLanguage = Localization.currentLanguage().localizationFileName
        guard let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj") else { return NSLocalizedString(rawValue, comment: "") }
        guard let bundle = Bundle(path: path) else { return NSLocalizedString(rawValue, comment: "") }
        var localizationKey = ""
        
        if intNumber == 0 {
            localizationKey = rawValue + ".many"
        } else if intNumber % 10 == 1 && intNumber % 100 != 11 {
            localizationKey = rawValue + ".one"
        } else if (intNumber % 10 >= 2 && intNumber % 10 <= 4) && !(intNumber % 100 >= 12 && intNumber % 100 < 14) {
            localizationKey = rawValue + ".other"
        } else if intNumber % 10 == 0 || (intNumber % 10 >= 5 && intNumber % 10 <= 9) || (intNumber % 100 >= 11 && intNumber % 100 <= 14) {
            localizationKey = rawValue + ".many"
        }
        
        let formatString = bundle.localizedString(forKey: localizationKey, value: "", table: nil)
        return String(format: formatString, intNumber)
    }
}

extension Localization {
    
    ///Localization code for current interface language
    static var currentLocale: Locale {
        return Locale(identifier: Localization.currentLanguage().localizationCode)
    }
    
    ///Set language code of selected interface language to UserDefaults
    /// - Parameters:
    ///   - language: Language model related to selected language
    static func setCurrentLanguage(_ language: Language?) {
        guard let language = language else {
            let defaultLanguage = Language(rawValue: "en")!
            UserDefaultsManager.userDefaults.setValue(defaultLanguage.rawValue, forKey: LanguageSettingsKey)
            return
        }
        UserDefaultsManager.userDefaults.setValue(language.rawValue, forKey: LanguageSettingsKey)
    }
    
    ///Get translated string related to API constants (e.g.: interest type).
    /// - Parameters:
    ///   - key: string received from API which should be localized
    /// - Returns: translated string
    static func translation(for key: String) -> String {
        let selectedLanguage = Localization.currentLanguage().localizationFileName
        guard let path = Bundle.main.path(forResource: selectedLanguage, ofType: "lproj") else { return "" }
        guard let bundle = Bundle(path: path) else { return "" }
        return bundle.localizedString(forKey: key, value: "", table: nil)
    }
    
    ///Get interface language selected by user. By default it is device language.
    /// - Returns: selected Language model
    static func currentLanguage() -> Language {
        let languageCode = UserDefaultsManager.userDefaults.string(forKey: LanguageSettingsKey)
        var language: Language
        if let languageCode {
            language = Language(rawValue: languageCode) ?? Language.defaultLanguage()
        } else {
            let deviceLanguageCode = Locale.current.languageCode ?? ""
            language = Language(rawValue: deviceLanguageCode) ?? Language.defaultLanguage()
            setCurrentLanguage(language)
        }
        return language
    }
    
    ///Get available languages that users can choose for the interface
    /// - Returns: List of Language models
    static func availableLanguages() -> [Language] {
        return [Language(rawValue: "en")!, Language(rawValue: "ua")!, Language(rawValue: "es")!, Language(rawValue: "de")!, Language(rawValue: "fr")!, Language(rawValue: "ru")!]
    }
    
    ///Get the URL for the HTML file with the user role description
    /// - Returns: file URL
    static func authUserDescription() -> URL {
        let code = Localization.currentLanguage().localizationCode
        return Bundle.main.url(forResource: "user_description_\(code)", withExtension: "html")!
    }
    
    ///Get the url for the HTML file with the influencer role description
    /// - Returns: file URL
    static func authInfluencerDescription() -> URL {
        let code = Localization.currentLanguage().localizationCode
        return Bundle.main.url(forResource: "influencer_description_\(code)", withExtension: "html")!
    }
}
