//
//  HomeViewController.swift
//  AnimeLounge
//
//  Created by Francesco on 21/06/24.
//

import UIKit
import SwiftSoup

class HomeViewController: UITableViewController, SourceSelectionDelegate {
    
    @IBOutlet private weak var airingCollectionView: UICollectionView!
    @IBOutlet private weak var trendingCollectionView: UICollectionView!
    @IBOutlet private weak var seasonalCollectionView: UICollectionView!
    @IBOutlet private weak var featuredCollectionView: UICollectionView!
    @IBOutlet private weak var continueWatchingCollectionView: UICollectionView!
    
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var selectedSourceLabel: UILabel!
    
    private var airingAnime: [Anime] = []
    private var trendingAnime: [Anime] = []
    private var seasonalAnime: [Anime] = []
    private var featuredAnime: [AnimeItem] = []
    private var continueWatchingItems: [ContinueWatchingItem] = []
    
    private let aniListServiceAiring = AnilistServiceAiringAnime()
    private let aniListServiceTrending = AnilistServiceTrendingAnime()
    private let aniListServiceSeasonal = AnilistServiceSeasonalAnime()
    
    private let funnyTexts: [String] = [
        "No shows here... did you just break the internet?",
        "Oops, looks like you finished everything! Try something fresh.",
        "You've watched it all! Time to rewatch or explore!",
        "Nothing left to watch... for now!",
        "All clear! Ready to start a new watch marathon?",
        "Your watchlist is taking a nap... Wake it up with something new!",
        "Nothing to continue here... maybe it's snack time?",
        "Looks empty... Wanna start a new adventure?",
        "All caught up! What’s next on the list?"
    ]
    
    private let emptyContinueWatchingLabel: UILabel = {
        let label = UILabel()
        label.textColor = .gray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupCollectionViews()
        setupDateLabel()
        setupSelectedSourceLabel()
        setupRefreshControl()
        setupEmptyContinueWatchingLabel()
        fetchAnimeData()
        updateCheck()
        
        SourceMenu.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadContinueWatchingItems()
    }
    
    private func setupEmptyContinueWatchingLabel() {
        emptyContinueWatchingLabel.frame = continueWatchingCollectionView.bounds
        continueWatchingCollectionView.backgroundView = emptyContinueWatchingLabel
    }

    func loadContinueWatchingItems() {
        continueWatchingItems = ContinueWatchingManager.shared.getItems()
        continueWatchingCollectionView.reloadData()
        
        if continueWatchingItems.isEmpty {
            let randomText = funnyTexts.randomElement() ?? "No anime here!"
            emptyContinueWatchingLabel.text = randomText
            emptyContinueWatchingLabel.isHidden = false
        } else {
            emptyContinueWatchingLabel.isHidden = true
        }
    }
    
    func setupCollectionViews() {
        let collectionViews = [continueWatchingCollectionView, airingCollectionView, trendingCollectionView, seasonalCollectionView, featuredCollectionView]
        let cellIdentifiers = ["ContinueWatchingCell", "AiringAnimeCell", "SlimmAnimeCell", "SlimmAnimeCell", "SlimmAnimeCell"]
        let cellClasses = [ContinueWatchingCell.self, UICollectionViewCell.self, UICollectionViewCell.self, UICollectionViewCell.self, UICollectionViewCell.self]

        for (index, collectionView) in collectionViews.enumerated() {
            collectionView?.delegate = self
            collectionView?.dataSource = self
            
            let identifier = cellIdentifiers[index]
            let cellClass = cellClasses[index]
            
            if identifier == "ContinueWatchingCell" {
                collectionView?.register(cellClass, forCellWithReuseIdentifier: identifier)
            } else {
                collectionView?.register(UINib(nibName: identifier, bundle: nil), forCellWithReuseIdentifier: identifier)
            }
        }
    }
    
    func setupDateLabel() {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, dd MMMM yyyy"
        let dateString = dateFormatter.string(from: currentDate)
        dateLabel.text = "on \(dateString)"
    }
    
    func setupSelectedSourceLabel() {
        let selectedSource = UserDefaults.standard.string(forKey: "selectedMediaSource") ?? "AnimeWorld"
        selectedSourceLabel.text = "on \(selectedSource)"
    }
    
    func setupRefreshControl() {
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refreshData), for: .valueChanged)
    }
    
    @objc func refreshData() {
        fetchAnimeData()
    }
    
    func fetchAnimeData() {
        let dispatchGroup = DispatchGroup()
        
        dispatchGroup.enter()
        fetchTrendingAnime { dispatchGroup.leave() }
        
        dispatchGroup.enter()
        fetchSeasonalAnime { dispatchGroup.leave() }
        
        dispatchGroup.enter()
        fetchAiringAnime { dispatchGroup.leave() }
        
        dispatchGroup.enter()
        fetchFeaturedAnime { dispatchGroup.leave() }
        
        dispatchGroup.notify(queue: .main) {
            self.refreshUI()
            self.refreshControl?.endRefreshing()
        }
    }
    
    func fetchTrendingAnime(completion: @escaping () -> Void) {
        aniListServiceTrending.fetchTrendingAnime { [weak self] animeList in
            self?.trendingAnime = animeList ?? []
            completion()
        }
    }
    
    func fetchSeasonalAnime(completion: @escaping () -> Void) {
        aniListServiceSeasonal.fetchSeasonalAnime { [weak self] animeList in
            self?.seasonalAnime = animeList ?? []
            completion()
        }
    }
    
    func fetchAiringAnime(completion: @escaping () -> Void) {
        aniListServiceAiring.fetchAiringAnime { [weak self] animeList in
            self?.airingAnime = animeList ?? []
            completion()
        }
    }
    
    private func fetchFeaturedAnime(completion: @escaping () -> Void) {
        let selectedSource = UserDefaults.standard.string(forKey: "selectedMediaSource") ?? "AnimeWorld"
        let (sourceURL, parseStrategy) = getSourceInfo(for: selectedSource)

        guard let urlString = sourceURL, let url = URL(string: urlString), let parse = parseStrategy else {
            completion()
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            
            do {
                let html = String(data: data, encoding: .utf8) ?? ""
                let doc: Document = try SwiftSoup.parse(html)
                
                let animeItems = try parse(doc)
                
                DispatchQueue.main.async {
                    self?.featuredAnime = animeItems
                    completion()
                }
            } catch {
                print("Error parsing HTML: \(error)")
                DispatchQueue.main.async {
                    completion()
                }
            }
        }.resume()
    }
    
    func refreshUI() {
        DispatchQueue.main.async {
            self.loadContinueWatchingItems()
            self.continueWatchingCollectionView.reloadData()
            self.airingCollectionView.reloadData()
            self.trendingCollectionView.reloadData()
            self.seasonalCollectionView.reloadData()
            self.featuredCollectionView.reloadData()
            self.setupDateLabel()
            self.setupSelectedSourceLabel()
        }
    }
    
    @IBAction func selectSourceButtonTapped(_ sender: UIButton) {
        SourceMenu.showSourceSelector(from: self, sourceView: sender)
    }
    
    func didSelectNewSource() {
        setupSelectedSourceLabel()
        fetchAnimeData()
    }
    
    func updateCheck() {
        UpdateChecker.shared.checkForUpdates { updateAvailable, appVersion in
            if updateAvailable, let version = appVersion {
                UpdateChecker.shared.showUpdateAlert(appVersion: version)
            }
        }
    }
}

extension HomeViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch collectionView {
        case continueWatchingCollectionView:
            return continueWatchingItems.count
        case trendingCollectionView:
            return trendingAnime.count
        case seasonalCollectionView:
            return seasonalAnime.count
        case airingCollectionView:
            return airingAnime.count
        case featuredCollectionView:
            return featuredAnime.count
        default:
            return 0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch collectionView {
        case continueWatchingCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ContinueWatchingCell", for: indexPath) as! ContinueWatchingCell
            let item = continueWatchingItems[indexPath.item]
            cell.configure(with: item)
            return cell
        case trendingCollectionView, seasonalCollectionView, featuredCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SlimmAnimeCell", for: indexPath)
            if let slimmCell = cell as? SlimmAnimeCell {
                configureSlimmCell(slimmCell, at: indexPath, for: collectionView)
            }
            return cell
        case airingCollectionView:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AiringAnimeCell", for: indexPath)
            if let airingCell = cell as? AiringAnimeCell {
                configureAiringCell(airingCell, at: indexPath)
            }
            return cell
        default:
            fatalError("Unexpected collection view")
        }
    }
    
    private func configureSlimmCell(_ cell: SlimmAnimeCell, at indexPath: IndexPath, for collectionView: UICollectionView) {
        switch collectionView {
        case trendingCollectionView:
            let anime = trendingAnime[indexPath.item]
            let imageUrl = URL(string: anime.coverImage.large)
            cell.configure(with: anime.title.romaji, imageUrl: imageUrl)
        case seasonalCollectionView:
            let anime = seasonalAnime[indexPath.item]
            let imageUrl = URL(string: anime.coverImage.large)
            cell.configure(with: anime.title.romaji, imageUrl: imageUrl)
        case featuredCollectionView:
            let anime = featuredAnime[indexPath.item]
            let imageUrl = URL(string: anime.imageURL)
            cell.configure(with: anime.title, imageUrl: imageUrl)
        default:
            break
        }
    }
    
    private func configureAiringCell(_ cell: AiringAnimeCell, at indexPath: IndexPath) {
        let anime = airingAnime[indexPath.item]
        let imageUrl = URL(string: anime.coverImage.large)
        cell.configure(
            with: anime.title.romaji,
            imageUrl: imageUrl,
            episodes: anime.episodes,
            description: anime.description,
            airingAt: anime.airingAt
        )
    }
}

extension HomeViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch collectionView {
        case continueWatchingCollectionView:
            let item = continueWatchingItems[indexPath.item]
            resumeWatching(item: item)
        case trendingCollectionView:
            let anime = trendingAnime[indexPath.item]
            navigateToAnimeDetail(for: anime)
        case seasonalCollectionView:
            let anime = seasonalAnime[indexPath.item]
            navigateToAnimeDetail(for: anime)
        case airingCollectionView:
            let anime = airingAnime[indexPath.item]
            navigateToAnimeDetail(for: anime)
        case featuredCollectionView:
            let anime = featuredAnime[indexPath.item]
            navigateToAnimeDetail(title: anime.title, imageUrl: anime.imageURL, href: anime.href)
        default:
            break
        }
    }

    private func resumeWatching(item: ContinueWatchingItem) {
        let detailVC = AnimeDetailViewController()
        detailVC.configure(title: item.animeTitle, imageUrl: item.imageURL, href: item.fullURL)
        
        let episode = Episode(number: String(item.episodeNumber), href: item.fullURL, downloadUrl: "")
        
        let dummyCell = EpisodeCell()
        dummyCell.episodeNumber = String(item.episodeNumber)
        
        detailVC.episodeSelected(episode: episode, cell: dummyCell)
        
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func navigateToAnimeDetail(for anime: Anime) {
        let storyboard = UIStoryboard(name: "AnilistAnimeInformation", bundle: nil)
        if let animeDetailVC = storyboard.instantiateViewController(withIdentifier: "AnimeInformation") as? AnimeInformation {
            animeDetailVC.animeID = anime.id
            navigationController?.pushViewController(animeDetailVC, animated: true)
        }
    }
    
    private func navigateToAnimeDetail(title: String, imageUrl: String, href: String) {
        let detailVC = AnimeDetailViewController()
        detailVC.configure(title: title, imageUrl: imageUrl, href: href)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

extension HomeViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let cell = interaction.view as? UICollectionViewCell,
              let indexPath = indexPathForCell(cell) else { return nil }
        
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: { [weak self] in
            self?.previewViewController(for: indexPath)
        }, actionProvider: { [weak self] _ in
            guard let self = self else { return nil }
            
            let openAction = UIAction(title: "Open", image: UIImage(systemName: "eye")) { _ in
                self.openAnimeDetail(for: indexPath)
            }
            
            let searchAction = UIAction(title: "Search Episodes", image: UIImage(systemName: "magnifyingglass")) { _ in
                self.searchEpisodes(for: indexPath)
            }
            
            return UIMenu(title: "", children: [openAction, searchAction])
        })
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = cellForIndexPath(indexPath) else {
            return nil
        }
        
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        
        return UITargetedPreview(view: cell, parameters: parameters)
    }
    
    private func previewViewController(for indexPath: IndexPath) -> UIViewController? {
        guard let anime = animeForIndexPath(indexPath) else { return nil }
        
        let storyboard = UIStoryboard(name: "AnilistAnimeInformation", bundle: nil)
        guard let animeDetailVC = storyboard.instantiateViewController(withIdentifier: "AnimeInformation") as? AnimeInformation else {
            return nil
        }
        
        animeDetailVC.animeID = anime.id
        return animeDetailVC
    }
    
    private func openAnimeDetail(for indexPath: IndexPath) {
        guard let anime = animeForIndexPath(indexPath) else { return }
        navigateToAnimeDetail(for: anime)
    }
    
    private func animeForIndexPath(_ indexPath: IndexPath) -> Anime? {
        switch indexPath.section {
        case 0:
            return trendingAnime[indexPath.item]
        case 1:
            return seasonalAnime[indexPath.item]
        case 2:
            return airingAnime[indexPath.item]
        case 3:
            return nil
        default:
            return nil
        }
    }
    
    private func indexPathForCell(_ cell: UICollectionViewCell) -> IndexPath? {
        let collectionViews = [trendingCollectionView, seasonalCollectionView, airingCollectionView, featuredCollectionView]
        
        for (section, collectionView) in collectionViews.enumerated() {
            if let indexPath = collectionView?.indexPath(for: cell) {
                return IndexPath(item: indexPath.item, section: section)
            }
        }
        return nil
    }
    
    private func cellForIndexPath(_ indexPath: IndexPath) -> UICollectionViewCell? {
         let collectionViews = [trendingCollectionView, seasonalCollectionView, airingCollectionView, featuredCollectionView]
         guard indexPath.section < collectionViews.count else { return nil }
         return collectionViews[indexPath.section]?.cellForItem(at: IndexPath(item: indexPath.item, section: 0))
     }

    private func searchEpisodes(for indexPath: IndexPath) {
        guard let anime = animeForIndexPath(indexPath) else { return }
        
        let query = anime.title.romaji
        guard !query.isEmpty else {
            showError(message: "Could not find anime title.")
            return
        }
        
        searchMedia(query: query)
    }
    
    private func searchMedia(query: String) {
        let resultsVC = SearchResultsViewController()
        resultsVC.query = query
        navigationController?.pushViewController(resultsVC, animated: true)
    }
    
    private func showError(message: String) {
        let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
}

class AnimeItem: NSObject {
    let title: String
    let episode: String
    let imageURL: String
    let href: String
    
    init(title: String, episode: String, imageURL: String, href: String) {
        self.title = title
        self.episode = episode
        self.imageURL = imageURL
        self.href = href
    }
}


struct Anime {
    let id: Int
    let title: Title
    let coverImage: CoverImage
    let episodes: Int?
    let description: String?
    let airingAt: Int?
    var mediaRelations: [MediaRelation] = []
    var characters: [Character] = []
}

struct MediaRelation {
    let node: MediaNode
    
    struct MediaNode {
        let id: Int
        let title: Title
    }
}

struct Character {
    let node: CharacterNode
    let role: String
    
    struct CharacterNode {
        let id: Int
        let name: Name
        
        struct Name {
            let full: String
        }
    }
}

struct Title {
    let romaji: String
    let english: String?
    let native: String?
}

struct CoverImage {
    let large: String
}
