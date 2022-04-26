//
//  LibraryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit

class LibraryViewController: MangaCollectionViewController {

    var unfilteredManga: [Manga] = [] {
        didSet {
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredManga.isEmpty
            }
        }
    }

    var unfilteredUpdatedManga: [Manga] = [] {
        didSet {
            Task { @MainActor in
                self.emptyTextStackView.isHidden = !self.unfilteredUpdatedManga.isEmpty
                self.collectionView?.alwaysBounceVertical = !self.unfilteredUpdatedManga.isEmpty
            }
        }
    }

    override var manga: [Manga] {
        get {
            unfilteredManga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        }
        set {
            unfilteredManga = newValue
        }
    }

    override var updatedManga: [Manga] {
        get {
            unfilteredUpdatedManga.filter { searchText.isEmpty ? true : $0.title?.lowercased().contains(searchText.lowercased()) ?? true }
        }
        set {
            unfilteredUpdatedManga = newValue
        }
    }

    var searchText: String = ""
    var updatedLibrary = false

    let emptyTextStackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LIBRARY", comment: "")

        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("LIBRARY_SEARCH", comment: "")
        navigationItem.searchController = searchController

        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        preloadsChapters = true
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

//        collectionView?.register(MangaListSelectionHeader.self,
//                                 forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
//                                 withReuseIdentifier: "MangaListSelectionHeader")

        emptyTextStackView.isHidden = true
        emptyTextStackView.axis = .vertical
        emptyTextStackView.distribution = .equalSpacing
        emptyTextStackView.spacing = 5
        emptyTextStackView.alignment = .center

        let emptyTitleLabel = UILabel()
        emptyTitleLabel.text = NSLocalizedString("LIBRARY_EMPTY", comment: "")
        emptyTitleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        emptyTitleLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTitleLabel)

        let emptyTextLabel = UILabel()
        emptyTextLabel.text = NSLocalizedString("LIBRARY_ADD_FROM_BROWSE", comment: "")
        emptyTextLabel.font = .systemFont(ofSize: 15)
        emptyTextLabel.textColor = .secondaryLabel
        emptyTextStackView.addArrangedSubview(emptyTextLabel)

        emptyTextStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyTextStackView)

        emptyTextStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        emptyTextStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        NotificationCenter.default.addObserver(forName: Notification.Name("updateLibrary"), object: nil, queue: nil) { _ in
            let previousManga = self.manga
            let previousUpdatedManga = self.updatedManga

            Task { @MainActor in
                var reordered = false
                await self.loadChaptersAndHistory()

                if !self.updatedManga.isEmpty && self.updatedManga.count == previousUpdatedManga.count {
                    self.collectionView?.performBatchUpdates {
                        for (i, manga) in previousUpdatedManga.enumerated() {
                            let from = IndexPath(row: i, section: 0)
                            if let j = self.updatedManga.firstIndex(where: { $0.sourceId == manga.sourceId && $0.id == manga.id }),
                               j != i {
                                let to = IndexPath(row: j, section: 0)
                                self.collectionView?.moveItem(at: from, to: to)
                            }
                        }

                        reordered = true
                    }
                }

                if !self.manga.isEmpty && self.manga.count == previousManga.count { // reorder
                    self.collectionView?.performBatchUpdates {
                        for (i, manga) in previousManga.enumerated() {
                            let from = IndexPath(row: i, section: 1)
                            if let j = self.manga.firstIndex(where: { $0.sourceId == manga.sourceId && $0.id == manga.id }),
                               j != i {
                                let to = IndexPath(row: j, section: 1)
                                self.collectionView?.moveItem(at: from, to: to)
                            }
                        }

                        reordered = true
                    }
                }

                if !reordered {
                    self.collectionView?.reloadData()
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        opensReaderView = UserDefaults.standard.bool(forKey: "Library.opensReaderView")
        badgeType = UserDefaults.standard.bool(forKey: "Library.unreadChapterBadges") ? .unread : .none

        super.viewWillAppear(animated)

        fetchLibrary()

        if !updatedLibrary {
            updatedLibrary = true
            Task {
                await DataManager.shared.updateLibrary()
                reloadData()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(updateLibraryRefresh), for: .valueChanged)
        collectionView?.refreshControl = refreshControl

        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func fetchLibrary() {
        Task {
            await loadChaptersAndHistory()
            reloadData()
        }
    }

    @objc func updateLibraryRefresh(refreshControl: UIRefreshControl) {
        Task {
            await DataManager.shared.updateLibrary()
            refreshControl.endRefreshing()
        }
    }

    func loadChaptersAndHistory() async {
        var tempManga: [Manga] = []
        var tempUpdatedManga: [Manga] = []

        for (i, m) in DataManager.shared.libraryManga.enumerated() {
            if opensReaderView || preloadsChapters || badgeType == .unread {
                if opensReaderView {
                    readHistory[m.id] = DataManager.shared.getReadHistory(manga: m)
                }

                chapters[m.id] = await DataManager.shared.getChapters(for: m)
                if badgeType == .unread {
                    if preloadsChapters {
                        readHistory[m.id] = DataManager.shared.getReadHistory(manga: m)
                    }

                    let badgeNum = (chapters[m.id]?.count ?? 0) - (readHistory[m.id]?.count ?? 0)
                    if badgeNum > 0 {
                        tempUpdatedManga.append(m)
                    } else {
                        tempManga.append(m)
                    }

                    badges[m.id] = badgeNum
                    if let cell = collectionView?.cellForItem(at: IndexPath(row: i, section: 0)) as? MangaCoverCell {
                        cell.badgeNumber = badges[m.id]
                    }
                }
            } else {
                chapters = [:]
                readHistory = [:]
            }
        }

        self.manga = tempManga
        self.updatedManga = tempUpdatedManga
    }
}

// MARK: - Library view overrides
extension LibraryViewController {
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        2
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 {
            return updatedManga.count
        } else {
            return manga.count
        }
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaCoverCell", for: indexPath) as? MangaCoverCell
        if cell == nil {
            cell = MangaCoverCell(frame: .zero)
        }

        if indexPath.section == 0 {
            if updatedManga.count > indexPath.row {
                cell?.manga = updatedManga[indexPath.row]
                cell?.badgeNumber = badges[updatedManga[indexPath.row].id]
            }
        } else {
            if manga.count > indexPath.row {
                cell?.manga = manga[indexPath.row]
                cell?.badgeNumber = badges[manga[indexPath.row].id]
            }
        }

        return cell ?? UICollectionViewCell()
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? MangaCoverCell)?.badgeNumber = badges[indexPath.section == 0 ? updatedManga[indexPath.row].id : manga[indexPath.row].id]
    }
}

// MARK: - Collection View Delegate
extension LibraryViewController: UICollectionViewDelegateFlowLayout {

//    func collectionView(_ collectionView: UICollectionView,
//                        layout collectionViewLayout: UICollectionViewLayout,
//                        referenceSizeForHeaderInSection section: Int) -> CGSize {
//        CGSize(width: collectionView.bounds.width, height: 40)
//    }
//
//    func collectionView(_ collectionView: UICollectionView,
//                        viewForSupplementaryElementOfKind kind: String,
//                        at indexPath: IndexPath) -> UICollectionReusableView {
//        if kind == UICollectionView.elementKindSectionHeader {
//            var header = collectionView.dequeueReusableSupplementaryView(
//                ofKind: kind,
//                withReuseIdentifier: "MangaListSelectionHeader",
//                for: indexPath
//            ) as? MangaListSelectionHeader
//            if header == nil {
//                header = MangaListSelectionHeader(frame: .zero)
//            }
//            header?.delegate = nil
//            header?.options = ["Default"]
//            header?.selectedOption = 0
//            header?.delegate = self
//            return header ?? UICollectionReusableView()
//        }
//        return UICollectionReusableView()
//    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard manga.count > indexPath.row || updatedManga.count > indexPath.row else { return }
        let manga = indexPath.section == 0 ? updatedManga[indexPath.row] : manga[indexPath.row]
        if opensReaderView,
           let chapter = getNextChapter(for: manga),
           SourceManager.shared.source(for: manga.sourceId) != nil {
            let readerController = ReaderViewController(manga: manga, chapter: chapter, chapterList: chapters[manga.id] ?? [])
            let navigationController = ReaderNavigationController(rootViewController: readerController)
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        } else {
            openMangaView(for: indexPath.section == 0 ? self.updatedManga[indexPath.row] : self.manga[indexPath.row])
        }

        DataManager.shared.setOpened(manga: indexPath.section == 0 ? updatedManga[indexPath.row] : self.manga[indexPath.row])
    }
}

// MARK: - Listing Header Delegate
extension LibraryViewController: MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int) {
        fetchLibrary()
    }
}

// MARK: - Search Results Updater
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        collectionView?.reloadData()
    }
}
