//
//  M2GameManager.m
//  m2048
//
//  Created by Danqing on 3/16/14.
//  Copyright (c) 2014 Danqing. All rights reserved.
//

#import "M2GameManager.h"
#import "M2Grid.h"
#import "M2Tile.h"
#import "M2Scene.h"
#import "M2ViewController.h"

/**
 * Helper function that checks the termination condition of either counting up or down.
 *
 * @param value The current i value.
 * @param countUp If YES, we are counting up.
 * @param upper The upper bound of i.
 * @param lower The lower bound of i.
 * @return YES if the counting is still in progress. NO if it should terminate.
 */
BOOL iterate(NSInteger value, BOOL countUp, NSInteger upper, NSInteger lower) {
  return countUp ? value < upper : value > lower;
}


@implementation M2GameManager {
  /** True if game over. */
  BOOL _over;
  
  /** True if won game. */
  BOOL _won;
  
  /** True if user chooses to keep playing after winning. */
  BOOL _keepPlaying;
  
  /** The current score. */
  NSInteger _score;
  
  /** The points earned by the user in the current round. */
  NSInteger _pendingScore;
  
  /** The grid on which everything happens. */
  M2Grid *_grid;

  /** The display link to add tiles after removing all existing tiles. */
  CADisplayLink *_addTileDisplayLink;
}


# pragma mark - Setup

- (void)startNewSessionWithScene:(M2Scene *)scene
{
  if (_grid) [_grid removeAllTilesAnimated:NO];
  if (!_grid || _grid.dimension != GSTATE.dimension) {
    _grid = [[M2Grid alloc] initWithDimension:GSTATE.dimension];
    _grid.scene = scene;
  }
  
  [scene loadBoardWithGrid:_grid];
  
  // Set the initial state for the game.
  _score = 0; _over = NO; _won = NO; _keepPlaying = NO;

  // Existing tile removal is async and happens in the next screen refresh, so we'd wait a bit.
  _addTileDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(addTwoRandomTiles)];
  [_addTileDisplayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}


- (void)addTwoRandomTiles
{
  // If the scene only has one child (the board), we can proceed with adding new tiles
  // since all old ones are removed. After adding new tiles, remove the displaylink.
  if (_grid.scene.children.count <= 1) {
    [_grid insertTileAtRandomAvailablePositionWithDelay:NO];
    [_grid insertTileAtRandomAvailablePositionWithDelay:NO];
    [_addTileDisplayLink invalidate];
  }
}


# pragma mark - Actions

- (void)moveToDirection:(M2Direction)direction
{
  __block M2Tile *tile = nil;
  
  // Remember that the coordinate system of SpriteKit is the reverse of that of UIKit.
  BOOL reverse = direction == M2DirectionUp || direction == M2DirectionRight;
  NSInteger unit = reverse ? 1 : -1;
  
  if (direction == M2DirectionUp || direction == M2DirectionDown) {
    [_grid forEach:^(M2Position position) {
      if ((tile = [self->_grid tileAtPosition:position])) {
        // Find farthest position to move to.
        NSInteger target = position.x;
        for (NSInteger i = position.x + unit; iterate(i, reverse, self->_grid.dimension, -1); i += unit) {
          M2Tile *t = [self->_grid tileAtPosition:M2PositionMake(i, position.y)];
          
          // Empty cell; we can move at least to here.
          if (!t) target = i;
          
          // Try to merge to the tile in the cell.
          else {
            NSInteger level = 0;
            
            if (GSTATE.gameType == M2GameTypePowerOf3) {
              M2Position further = M2PositionMake(i + unit, position.y);
              M2Tile *ft = [self->_grid tileAtPosition:further];
              if (ft) {
                level = [tile merge3ToTile:t andTile:ft];
              }
            } else {
              level = [tile mergeToTile:t];
            }
            
            if (level) {
              target = position.x;
              self->_pendingScore = [GSTATE valueForLevel:level];
            }

            break;
          }
        }
        
        // The current tile is movable.
        if (target != position.x) {
          [tile moveToCell:[self->_grid cellAtPosition:M2PositionMake(target, position.y)]];
          self->_pendingScore++;
        }
      }
    } reverseOrder:reverse];
  }
  
  else {
    [_grid forEach:^(M2Position position) {
      if ((tile = [self->_grid tileAtPosition:position])) {
        NSInteger target = position.y;
        for (NSInteger i = position.y + unit; iterate(i, reverse, self->_grid.dimension, -1); i += unit) {
          M2Tile *t = [self->_grid tileAtPosition:M2PositionMake(position.x, i)];
          
          if (!t) target = i;

          else {
            NSInteger level = 0;
            
            if (GSTATE.gameType == M2GameTypePowerOf3) {
              M2Position further = M2PositionMake(position.x, i + unit);
              M2Tile *ft = [self->_grid tileAtPosition:further];
              if (ft) {
                level = [tile merge3ToTile:t andTile:ft];
              }
            } else {
              level = [tile mergeToTile:t];
            }
            
            if (level) {
              target = position.y;
              self->_pendingScore = [GSTATE valueForLevel:level];
            }
            
            break;
          }
        }
        
        // The current tile is movable.
        if (target != position.y) {
          [tile moveToCell:[self->_grid cellAtPosition:M2PositionMake(position.x, target)]];
          self->_pendingScore++;
        }
      }
    } reverseOrder:reverse];
  }
  
  // Cannot move to the given direction. Abort.
  if (!_pendingScore) return;
  
  // Commit tile movements.
  [_grid forEach:^(M2Position position) {
    M2Tile *tile = [self->_grid tileAtPosition:position];
    if (tile) {
      [tile commitPendingActions];
      if (tile.level >= GSTATE.winningLevel) self->_won = YES;
    }
  } reverseOrder:reverse];
  
  // Increment score.
  [self materializePendingScore];
  
  // Check post-move status.
  if (!_keepPlaying && _won) {
    // We set `keepPlaying` to YES. If the user decides not to keep playing,
    // we will be starting a new game, so the current state is no longer relevant.
    _keepPlaying = YES;
    [_grid.scene.controller endGame:YES];
  }
    
  // Add one more tile to the grid.
  [_grid insertTileAtRandomAvailablePositionWithDelay:YES];
  if (GSTATE.dimension == 5 && GSTATE.gameType == M2GameTypePowerOf2)
    [_grid insertTileAtRandomAvailablePositionWithDelay:YES];
    
  if (![self movesAvailable]) {
    [_grid.scene.controller endGame:NO];
  }
}


# pragma mark - Score

- (void)materializePendingScore
{
  _score += _pendingScore;
  _pendingScore = 0;
  [_grid.scene.controller updateScore:_score];
}


# pragma mark - State checkers

/**
 * Whether there are moves available.
 *
 * A move is available if either there is an empty cell, or there are adjacent matching cells. 
 * The check for matching cells is more expensive, so it is only performed when there is no
 * available cell.
 *
 * @return YES if there are moves available.
 */
- (BOOL)movesAvailable
{
  return [_grid hasAvailableCells] || [self adjacentMatchesAvailable];
}


/**
 * Whether there are adjacent matches available.
 *
 * An adjacent match is present when two cells that share an edge can be merged. We do not
 * consider cases in which two mergable cells are separated by some empty cells, as that should
 * be covered by the `cellsAvailable` function.
 *
 * @return YES if there are adjacent matches available.
 */
- (BOOL)adjacentMatchesAvailable
{
  for (NSInteger i = 0; i < _grid.dimension; i++) {
    for (NSInteger j = 0; j < _grid.dimension; j++) {
      // Due to symmetry, we only need to check for tiles to the right and down.
      M2Tile *tile = [_grid tileAtPosition:M2PositionMake(i, j)];
      
      // Continue with next iteration if the tile does not exist. Note that this means that
      // the cell is empty. For our current usage, it will never happen. It is only in place
      // in case we want to use this function by itself.
      if (!tile) continue;
      
      if (GSTATE.gameType == M2GameTypePowerOf3) {
        if (([tile canMergeWithTile:[_grid tileAtPosition:M2PositionMake(i + 1, j)]] &&
             [tile canMergeWithTile:[_grid tileAtPosition:M2PositionMake(i + 2, j)]]) ||
            ([tile canMergeWithTile:[_grid tileAtPosition:M2PositionMake(i, j + 1)]] &&
             [tile canMergeWithTile:[_grid tileAtPosition:M2PositionMake(i, j + 2)]])) {
          return YES;
        }
      } else {
        if ([tile canMergeWithTile:[_grid tileAtPosition:M2PositionMake(i + 1, j)]] ||
            [tile canMergeWithTile:[_grid tileAtPosition:M2PositionMake(i, j + 1)]]) {
          return YES;
        }
      }
    }
  }
  
  // Nothing is found.
  return NO;
}

@end
