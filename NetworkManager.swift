//
//  NetworkManagerManager.swift
//
//  Created by Sasha Klovak on 25.11.2020.
//

import Foundation
import Moya
import KeychainSwift

///For RequestType
typealias NetworkCompletion<T> = ((T?, ErrorModel?) -> ()) where T: Codable
typealias ProgressHandler = ((CGFloat) -> ())//progress: CGFloat = 0.0 .. 1.0

//For MediaRequestType
typealias NetworkMediaCompletion = (([ObservableMediaModel]?, ErrorModel?) -> ())

enum NetworkConnectionType: String {
    case wifi = "NetworkConnectionTypeWiFi"
    case cellular = "NetworkConnectionTypeCellular"
    case none = "NetworkConnectionTypeUnknown"
}

enum EnvType: String, CaseIterable {
    case dev = "dev"
    case test = "test"
    case stage = "stage"
    case prod = "production"
}

extension EnvType {
    var title: String {
        switch self {
        case .dev:
            return "Dev"
        case .test:
            return "Test"
        case .stage:
            return "Stage"
        case .prod:
            return "Production"
        }
    }
    
    var host: String {
        switch self {
        case .dev:
            return "dev.api.noname.com"
        case .test:
            return "test.api.noname.com"
        case .stage:
            return "stage.api.noname.com"
        case .prod:
            return "api.noname.com"
        }
    }
    
    var frontentUrl: String {
        switch self {
        case .dev:
            return "https://dev.noname.com"
        case .test:
            return "https://test.noname.com"
        case .stage:
            return "https://stage.noname.com"
        case .prod:
            return "https://noname.com"
        }
    }
}

let NetworkRefreshingStartedNotification: NSNotification.Name = NSNotification.Name(rawValue: "NetworkRefreshingStartedNotification")
let NetworkRefreshingFinishedNotification: NSNotification.Name = NSNotification.Name(rawValue: "NetworkRefreshingFinishedNotification")
let NetworkRefreshingInProgressKey: String = "NetworkRefreshingStartedKey"


fileprivate struct ActiveRequestModel {
    let index: Int
    let request: Cancellable
}


final class NetworkManager {
        
    private let provider = MoyaProvider<RequestType>()
    
    ///List of all active requests.
    ///It is necessary to have the possibility to cancel active requests.
    private var activeRequests: [ActiveRequestModel] = []
    
    ///It indicates whether we can make a request or access token is refreshing right now and we need to wait until it finished
    private var refreshInProgress: Bool = false
        
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleStartRefresh), name: NetworkRefreshingStartedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFinishRefresh), name: NetworkRefreshingFinishedNotification, object: nil)
        refreshInProgress = isRefreshingInProgress()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    ///Make request without progress handling
    /// - Parameters:
    ///   - type:  API request to be executed
    ///   - expectedType: Type of model we expect to get in response. The model should conform to Codable.
    ///   - completion: Closure that performed when a response is received.
    func request<T>(_ type: RequestType, expectedType: T.Type, completion: @escaping NetworkCompletion<T>) where T: Codable {
        let index = activeRequests.count
        let request = provider.request(type) { [weak self] (result) in
            self?.handleResult(result, type: type, expectedType: expectedType, completion: completion)
            self?.removeRequest(at: index)
        }
        activeRequests.append(ActiveRequestModel(index: index, request: request))
    }
    
    ///Make request with progress handling. Use for upload video/audio files.
    /// - Parameters:
    ///   - type:  API request to be executed
    ///   - expectedType: Type of model we expect to get in response. The model should conform to Codable.
    ///   - progressHandler: Closure that performed whenever progress changes.
    ///   - completion: Closure that performed when a response is received.
    func request<T>(_ type: RequestType, expectedType: T.Type, progressHandler: @escaping ProgressHandler, completion: @escaping NetworkCompletion<T>) where T: Codable {
        let index = activeRequests.count
        let request = provider.request(type, callbackQueue: .main) { (response) in
            progressHandler(CGFloat(response.progressObject?.fractionCompleted ?? 0.0))
        } completion: { [weak self] (result) in
            self?.handleResult(result, type: type, expectedType: expectedType, completion: completion)
            self?.removeRequest(at: index)
        }
        activeRequests.append(ActiveRequestModel(index: index, request: request))
    }
    
    ///Handle result of request
    ///In case of success status parse model of `expectedType`
    ///In case of failure status or parsing error  handle `error`
    /// - Parameters:
    ///   - result: Request result included optional response and error
    ///   - type:  API request that was executed
    ///   - expectedType: Type of model we expect to get in response. The model should conform to Codable.
    ///   - progressHandler: Closure that performed whenever progress changes.
    ///   - completion: Closure that performed when a response is received.
    func handleResult<T>(_ result: Result<Moya.Response, MoyaError>, type: RequestType, expectedType: T.Type, progressHandler: ProgressHandler? = nil, completion: @escaping NetworkCompletion<T>) where T: Codable {
        switch result {
        case .success(let response):
            if let _ = expectedType as? EmptyModel.Type {
                do {
                    let errorModel = try response.map(ErrorModel.self)
                    self.handleError(errorModel, requestType: type, expectedType: expectedType, progressHandler: progressHandler, completion: completion, mediaCompletion: nil)
                } catch {
                    completion(EmptyModel() as? T, nil)
                }
                return
            }
            do {
                if response.statusCode < 300 {
                    let model = try response.map(expectedType.self)
                    completion(model, nil)
                } else {
                    let errorModel = try response.map(ErrorModel.self)
                    self.handleError(errorModel, requestType: type, expectedType: expectedType, progressHandler: progressHandler, completion: completion, mediaCompletion: nil)
                }
            } catch let error {
                print("Parcing error: error: \(error), request: \(type)")
                let errorModel = ErrorModel(statusCode: -1, message: [error.localizedDescription], timestamp: "", path: type.path)
                self.handleError(errorModel, requestType: type, expectedType: expectedType, progressHandler: progressHandler, completion: completion, mediaCompletion: nil)
            }
        case .failure(let error):
            let errorModel = ErrorModel(statusCode: error.errorCode, message: [error.localizedDescription], timestamp: "", path: type.path)
            self.handleError(errorModel, requestType: type, expectedType: expectedType, progressHandler: progressHandler, completion: completion, mediaCompletion: nil)
        }
    }

    ///Cancel all active requests
    func cancelRequests() {
        activeRequests.forEach { $0.request.cancel() }
        activeRequests.removeAll()
    }

    ///Remove access token refresh info
    static func clearRefreshInfo() {
        UserDefaultsManager.userDefaults.removeObject(forKey: NetworkRefreshingInProgressKey)
    }
}

private extension NetworkManager {
        
    ///Handle error of response
    ///If error code is 401 try to refresh access token
    ///If error code is 429 show tooltip with Too many requests message
    ///Otherwise perform completion with error
    /// - Parameters:
    ///   - error: model with all error information
    ///   - requestType: API request that was executed
    ///   - expectedType: Type of model we expect to get in response. The model should conform to Codable.
    ///   - progressHandler: Closure that performed whenever progress changes.
    ///   - completion: Closure that performed when a response is received. Only for `RequestType`
    ///   - mediaCompletion: Closure that performed when a response is received. Only for `MediaRequestType`
    func handleError<T>(_ error: ErrorModel, requestType: TargetType, expectedType: T.Type, progressHandler: ProgressHandler? = nil, completion: NetworkCompletion<T>? = nil, mediaCompletion: NetworkMediaCompletion? = nil) where T: Codable {
        //if status code == 401 - refresh token
        if error.statusCode == 401 {
            refreshToken(expectedType: expectedType, requestType: requestType, progressHandler: progressHandler, completion: completion, mediaCompletion: mediaCompletion)
        } else if error.statusCode == 429 {
            let tooltip = Tooltip.createErrorTooltip(with: Localization.errorTooManyRequests.value, autoHide: 3.0)
            tooltip.show()
        } else {
            completion?(nil, error)
            mediaCompletion?(nil, error)
        }
    }
    
    ///Refresh access token
    ///In case of success status save enw `access token` and `refresh token` and perform `requestType` again
    ///In case of failure status send logout notification
    /// - Parameters:
    ///   - requestType: API request that was executed
    ///   - expectedType: Type of model we expect to get in response. The model should conform to Codable.
    ///   - progressHandler: Closure that performed whenever progress changes.
    ///   - completion: Closure that performed when a response is received. Only for `RequestType`
    ///   - mediaCompletion: Closure that performed when a response is received. Only for `MediaRequestType`
    func refreshToken<T>(expectedType: T.Type, requestType: TargetType, progressHandler: ProgressHandler? = nil, completion: NetworkCompletion<T>?, mediaCompletion: NetworkMediaCompletion?) where T: Codable {
        if refreshInProgress {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if let requestType = requestType as? MediaRequestType, let mediaCompletion {
                    self?.requestMediaList(requestType, expectedType: expectedType, completion: mediaCompletion)
                } else if let requestType = requestType as? RequestType, let completion {
                    if let handler = progressHandler {
                        self?.request(requestType, expectedType: expectedType, progressHandler: handler, completion: completion)
                    } else {
                        self?.request(requestType, expectedType: expectedType, completion: completion)
                    }
                }
            }
            return
        }
        didStartRefreshing()
        provider.request(.refreshTokens(["refreshToken" : AuthManager.refreshToken() ?? ""])) { [weak self] (result) in
            self?.didFinishRefreshing()
            switch result {
            case .success(let response):
                do {
                    if response.statusCode < 300 {
                        let tokenModel = try response.map(TokenModel.self)
                        AuthManager.saveToken(tokenModel)
                        if let requestType = requestType as? MediaRequestType, let mediaCompletion {
                            self?.requestMediaList(requestType, expectedType: expectedType, completion: mediaCompletion)
                        } else if let requestType = requestType as? RequestType, let completion {
                            if let handler = progressHandler {
                                self?.request(requestType, expectedType: expectedType, progressHandler: handler, completion: completion)
                            } else {
                                self?.request(requestType, expectedType: expectedType, completion: completion)
                            }
                        }
                    } else {
                        let errorModel = try response.map(ErrorModel.self)
                        completion?(nil, errorModel)
                        mediaCompletion?(nil, errorModel)
                        if AuthManager.isAuthorized() && errorModel.statusCode != 503 {
                            NotificationCenter.default.post(name: NetworkLogoutNotification, object: nil)
                        }
                    }
                } catch let error {
                    let errorModel = ErrorModel(statusCode: -1, message: [error.localizedDescription], timestamp: "", path: requestType.path)
                    completion?(nil, errorModel)
                    mediaCompletion?(nil, errorModel)
                }
            case .failure(let error):
                let errorModel = ErrorModel(statusCode: error.errorCode, message: [error.localizedDescription], timestamp: "", path: requestType.path)
                completion?(nil, errorModel)
                mediaCompletion?(nil, errorModel)
                break
            }
        }
    }
    
    func removeRequest(at index: Int) {
        if activeRequests.count > index {
            activeRequests.remove(at: index)
        }
    }
}

//token refreshing handling
private extension NetworkManager {

    func didStartRefreshing() {
        UserDefaultsManager.userDefaults.set(true, forKey: NetworkRefreshingInProgressKey)
        NotificationCenter.default.post(name: NetworkRefreshingStartedNotification, object: nil)
        refreshInProgress = true
    }

    func didFinishRefreshing() {
        UserDefaultsManager.userDefaults.removeObject(forKey: NetworkRefreshingInProgressKey)
        NotificationCenter.default.post(name: NetworkRefreshingFinishedNotification, object: nil)
        refreshInProgress = false
    }

    func isRefreshingInProgress() -> Bool {
        return UserDefaultsManager.userDefaults.bool(forKey: NetworkRefreshingInProgressKey)
    }

    @objc func handleStartRefresh() {
        refreshInProgress = true
    }

    @objc func handleFinishRefresh() {
        refreshInProgress = false
    }
}

extension NetworkManager {
    private static let BaseHostKey = "BaseHostKey"
    
    static var baseApiURL: String {
        #if DEBUG
        let hostString = UserDefaultsManager.userDefaults.string(forKey: BaseHostKey) ?? "dev"
        let currentHost = EnvType(rawValue: hostString) ?? .dev
        return "https://\(currentHost.host)/"
        #else
        return "https://\(EnvType.prod.host)/"
        #endif
    }
    
    static var baseImageURL: String {
        #if DEBUG
        let hostString = UserDefaultsManager.userDefaults.string(forKey: BaseHostKey) ?? "dev"
        let currentHost = EnvType(rawValue: hostString) ?? .dev
        return "https://pix.\(currentHost.host)/"
        #else
        return "https://pix.\(EnvType.prod.host)/"
        #endif
    }
    
    static var baseCdnURL: String {
        #if DEBUG
        let hostString = UserDefaultsManager.userDefaults.string(forKey: BaseHostKey) ?? "dev"
        let currentHost = EnvType(rawValue: hostString) ?? .dev
        return "https://cdn.\(currentHost.host)/"
        #else
        return "https://cdn.\(EnvType.prod.host)/"
        #endif
    }
    
    static func setHost(_ hostType: EnvType) {
        UserDefaultsManager.userDefaults.set(hostType.rawValue, forKey: NetworkManager.BaseHostKey)
    }
    
    static func currentEnvironment() -> EnvType {
        let type = UserDefaultsManager.userDefaults.string(forKey: BaseHostKey) ?? "dev"
        return EnvType(rawValue: type) ?? .dev
    }
}

extension NetworkManager {
    
    private static let ConnectionAvailabilityKey = "ConnectionAvailabilityKey"
    
    static func saveConnectionAvailability(_ isAvailable: Bool) {
        UserDefaultsManager.userDefaults.setValue(isAvailable, forKey: ConnectionAvailabilityKey)
    }
    
    static func isConnectionAvailable() -> Bool {
        return UserDefaultsManager.userDefaults.bool(forKey: ConnectionAvailabilityKey)
    }
}

extension NetworkManager {
    
    private static let NetworkConnectionTypeKey = "NetworkConnectionTypeKey"
    
    static func saveNetworkConnectionType(_ type: NetworkConnectionType) {
        UserDefaultsManager.userDefaults.setValue(type.rawValue, forKey: NetworkConnectionTypeKey)
    }
    
    static func networkConnectionType() -> NetworkConnectionType {
        if let rawValue = UserDefaultsManager.userDefaults.string(forKey: NetworkConnectionTypeKey) {
            return NetworkConnectionType(rawValue: rawValue) ?? .none
        }
        return .none
    }
}
