//
//  UserManager.m
//  PhotoHunt

#import "FSHAccessToken.h"
#import "FSHSession.h"
#import "GAI.h"
#import "GAITracker.h"
#import "GTLQueryFSH.h"
#import "GTMLogger.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "UserManager.h"

@implementation UserManager

- (id)init {
  return [self initWithDelegate:nil andService:nil];
}

- (id)initWithDelegate:(id<UserManagerDelegate>)delegate
            andService:(GTLServiceFSH *)gtlservice {
  self  = [super init];
  if (self) {
    self.delegate = delegate;
    self.service = gtlservice;
  }
  return self;
}

- (void)dealloc {
  [_currentAuth release];
  [_service release];
  [_currentUser release];
  [super dealloc];
}

- (BOOL)canSignIn {
  // Check whether we can sign in. If it looks like we should be able to sign in
  // then we return YES so that the caller can avoid taking extra action until
  // the user been retrieved. This call also kicks off the actual authentication
  // process, so we will attempt to seamlessly sign in, and call the usual
  // finishedWithAuth:error: delegate.
  return [[GPPSignIn sharedInstance] trySilentAuthentication];
}

- (void)signInAndRetrieveUser:(BOOL)attemptSSO {
  [GPPSignIn sharedInstance].attemptSSO = attemptSSO;
  [[GPPSignIn sharedInstance] authenticate];
}

- (void)signOut {
  [[GPPSignIn sharedInstance] signOut];
  self.currentAuth = nil;
  self.currentUser = nil;
}

- (void)finishedWithAuth:(GTMOAuth2Authentication *)auth
                   error:(NSError *) error {
  if (error) {
    [self.delegate userLoginFailed];
    GTMLoggerDebug(@"Auth Error: %@", error);
    return;
  }

  self.currentAuth = auth;
  [self refreshToken];
}

- (void)refreshToken {
  if (self.currentAuth) {
    [self.delegate startedAction];
  }

  [self.currentAuth authorizeRequest:nil completionHandler:^(NSError *error) {
      if (error) {
        GTMLoggerDebug(@"Token Fetch Error: %@", error);
        if ([error code] == 400) {
          // Our token is bad, clear it.
          [self signOut];
        }
        [self.delegate userLoginFailed];
        return;
      }

      FSHAccessToken *token = [FSHAccessToken object];
      token.access_token = [NSString stringWithFormat:@"%@",
                            self.currentAuth.accessToken];
      GTLQueryFSH *query = [GTLQueryFSH queryForSessionIdWithAccessToken:token];

      [self.service executeRestQuery:query completionHandler:
          ^(GTLServiceTicket *ticket,
            FSHSession *session,
            NSError *error) {
              if (error) {
                GTMLoggerDebug(@"Session Error: %@", error);
                [self.delegate userLoginFailed];
              } else {
                GTMLoggerDebug(@"Session Key: %@", session.session);
                if (self.currentUser) {
                  // No need to refresh user.
                  [self.delegate tokenRefreshed];
                  [self.delegate completedAction];
                } else {
                  [self retrieveProfile:[self selfIdentifier]];
                }
              }
      }];
  }];
}

- (void)retrieveProfile:(NSString *)userId {
  // Retrieve the users profile.
  GTLQueryFSH *profileQuery = [GTLQueryFSH queryForUserWithUserId:userId];
  [self.service executeRestQuery:profileQuery completionHandler:
      ^(GTLServiceTicket *ticket,
        FSHProfile *user,
        NSError *error) {
          if (error) {
            GTMLoggerDebug(@"User Error: %@", error);
            [self.delegate userLoginFailed];
          } else if ([userId isEqualToString:[self selfIdentifier]]) {
              self.currentUser = user;
          }
        [self.delegate loadedUser:user fromId:userId];
        [self.delegate completedAction];
   }];
}

- (NSString *)selfIdentifier {
  return @"me";
}

@end
